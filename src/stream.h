/**
 * @file src/stream.h
 * @brief Declarations for the streaming protocols.
 */
#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <boost/asio.hpp>

#include "audio.h"
#include "crypto.h"
#include "video.h"

namespace rtsp_stream {
  struct launch_session_t;
}

namespace stream {
  constexpr auto VIDEO_STREAM_PORT = 9;
  constexpr auto CONTROL_PORT = 10;
  constexpr auto AUDIO_STREAM_PORT = 11;
  constexpr auto MIC_STREAM_PORT = 12;  // Port for microphone streaming

  namespace ds5_audio {
    inline constexpr std::uint8_t STREAM_START = 1u << 0;
    inline constexpr std::uint8_t STREAM_END = 1u << 1;
    inline constexpr std::uint8_t DISCONTINUITY = 1u << 2;
    inline constexpr std::uint8_t ALLOWED_FLAGS = STREAM_START | STREAM_END | DISCONTINUITY;
    inline constexpr std::uint16_t MAX_FRAMES = 240;
    inline constexpr std::size_t BYTES_PER_FRAME = 8;
    inline constexpr std::size_t WIRE_HEADER_SIZE = 28;

    enum class route_e {
      quad_controller_audio,
      raw_haptics,
      authored_ir,
      legacy_rumble,
    };

    constexpr route_e
    select_route(bool controller_audio_preference, bool quad_supported,
                 bool raw_haptics_supported, bool authored_ir_supported) noexcept {
      if (controller_audio_preference && quad_supported) return route_e::quad_controller_audio;
      if (raw_haptics_supported) return route_e::raw_haptics;
      if (authored_ir_supported) return route_e::authored_ir;
      return route_e::legacy_rumble;
    }

    constexpr bool
    valid_packet(std::uint8_t flags, std::uint16_t frame_count,
                 const std::uint8_t *pcm, std::size_t pcm_size) noexcept {
      if ((flags & ~ALLOWED_FLAGS) != 0 || frame_count > MAX_FRAMES) return false;
      if (frame_count == 0) return flags == STREAM_END && pcm_size == 0;
      return pcm != nullptr && pcm_size == static_cast<std::size_t>(frame_count) * BYTES_PER_FRAME;
    }

    inline std::vector<std::uint8_t>
    encode_wire(std::uint16_t controller_id, std::uint8_t flags,
                std::uint16_t frame_count, std::uint32_t sequence,
                std::uint64_t presentation_time_us, const std::uint8_t *pcm,
                std::size_t pcm_size) {
      if (!valid_packet(flags, frame_count, pcm, pcm_size)) return {};
      std::vector<std::uint8_t> wire(WIRE_HEADER_SIZE + pcm_size);
      auto write_u16 = [](std::uint8_t *p, std::uint16_t v) {
        p[0] = static_cast<std::uint8_t>(v);
        p[1] = static_cast<std::uint8_t>(v >> 8);
      };
      auto write_u32 = [](std::uint8_t *p, std::uint32_t v) {
        p[0] = static_cast<std::uint8_t>(v);
        p[1] = static_cast<std::uint8_t>(v >> 8);
        p[2] = static_cast<std::uint8_t>(v >> 16);
        p[3] = static_cast<std::uint8_t>(v >> 24);
      };
      auto write_u64 = [&write_u32](std::uint8_t *p, std::uint64_t v) {
        write_u32(p, static_cast<std::uint32_t>(v));
        write_u32(p + 4, static_cast<std::uint32_t>(v >> 32));
      };
      wire[0] = 1;
      wire[1] = flags;
      write_u16(wire.data() + 2, WIRE_HEADER_SIZE);
      write_u16(wire.data() + 4, controller_id);
      write_u16(wire.data() + 6, frame_count);
      write_u32(wire.data() + 8, sequence);
      write_u64(wire.data() + 12, presentation_time_us);
      write_u32(wire.data() + 20, 48'000);
      wire[24] = 4;
      wire[25] = 16;
      wire[26] = wire[27] = 0;
      if (pcm_size != 0) std::copy_n(pcm, pcm_size, wire.data() + WIRE_HEADER_SIZE);
      return wire;
    }
  }  // namespace ds5_audio

  /**
   * @brief Convert a steady-clock presentation time to the 90 kHz RTP video clock.
   *
   * The conversion is performed with a signed intermediate so timestamps just
   * before the epoch round correctly before the final RTP modulo-2^32 cast.
   */
  std::uint32_t
  video_rtp_timestamp(
    std::chrono::steady_clock::time_point presentation_time,
    std::chrono::steady_clock::time_point epoch);

  struct session_t;
  struct config_t {
    audio::config_t audio;
    video::config_t monitor;

    int packetsize;
    int minRequiredFecPackets;
    int mlFeatureFlags;
    int controlProtocolType;
    int audioQosType;
    int videoQosType;

    uint32_t encryptionFlagsEnabled;

    std::optional<int> gcmap;
  };

  namespace session {
    enum class stop_reason_e : int {
      none,
      control_disconnect,
      control_timeout,
      protocol_error,
      video_ended,
      audio_ended,
      client_cancel,
      host_terminate,
    };

    const char *
    stop_reason_name(stop_reason_e reason);

    enum class state_e : int {
      STOPPED,  ///< The session is stopped
      STOPPING,  ///< The session is stopping
      STARTING,  ///< The session is starting
      RUNNING,  ///< The session is running
    };

    struct lifecycle_snapshot_t {
      state_e state;
      stop_reason_e stop_reason;
    };

    class lifecycle_t {
    public:
      explicit lifecycle_t(state_e initial_state = state_e::STOPPED) noexcept:
          _state(initial_state) {}

      state_e
      state() const noexcept {
        return _state.load(std::memory_order_acquire);
      }

      void
      set_state(state_e state) {
        std::lock_guard lock(_mutex);
        _state.store(state, std::memory_order_release);
      }

      bool
      request_stop(stop_reason_e reason) {
        std::lock_guard lock(_mutex);
        if (_state.load(std::memory_order_relaxed) != state_e::RUNNING) {
          return false;
        }

        _stop_reason = reason;
        _state.store(state_e::STOPPING, std::memory_order_release);
        return true;
      }

      lifecycle_snapshot_t
      snapshot() const {
        std::lock_guard lock(_mutex);
        return {
          _state.load(std::memory_order_relaxed),
          _stop_reason,
        };
      }

    private:
      mutable std::mutex _mutex;
      std::atomic<state_e> _state;
      stop_reason_e _stop_reason { stop_reason_e::none };
    };
  }  // namespace session

  // Session information structure for API responses
  struct session_info_t {
    std::string client_name;
    std::string client_uuid;
    std::string client_address;
    std::string state;
    std::string stop_reason;
    uint32_t session_id;
    std::int64_t uptime_ms;
    std::int64_t control_idle_ms;
    std::int64_t video_idle_ms;
    std::int64_t audio_idle_ms;
    bool control_connected;
    int width;
    int height;
    int fps;
    int bitrate;  // Current bitrate in Kbps
    bool host_audio;
    bool enable_hdr;
    bool enable_mic;
    bool use_vdd;
    bool hdr_brightness_reported;
    std::string hdr_brightness_source;
    float hdr_max_nits;
    float hdr_min_nits;
    float hdr_max_full_frame_nits;
    std::string app_name;
    int app_id;
  };

  namespace session {
    std::shared_ptr<session_t>
    alloc(config_t &config, rtsp_stream::launch_session_t &launch_session);
    int
    start(session_t &session, const std::string &addr_string);
    void
    stop(session_t &session, stop_reason_e reason = stop_reason_e::none);
    void
    join(session_t &session);
    state_e
    state(session_t &session);

    bool
    has_active_video_sessions();

    /**
     * @brief 请求统一的异步应用取消流程。
     *
     * 手动 /cancel 和“所有客户端断开后结束串流”都通过此函数进入同一条清理链路。
     * 函数只负责提交异步任务，不在调用线程中直接终止应用或恢复显示；任务会在 RTSP
     * 执行上下文中重新检查条件，并由完成回调释放去重标记、终止应用和恢复显示状态。
     *
     * @param source 用于本地日志的触发原因，不会作为外部协议数据发送。
     * @param require_no_video_session 是否要求任务执行时仍没有视频会话和待处理的 RTSP 票据。
     */
    void
    request_global_cancel(std::string_view source, bool require_no_video_session = false);
    


    /**
     * @brief Send dynamic parameter change event to a specific client session.
     * @param client_name The name of the client to target.
     * @param param The dynamic parameter to change.
     * @return true if the event was sent successfully, false otherwise.
     */
    bool
    change_dynamic_param_for_client(const std::string &client_name, const video::dynamic_param_t &param);

    /**
     * @brief Get information about all active sessions.
     * @return Vector of session information.
     */
    std::vector<session_info_t>
    get_all_sessions_info();
  }  // namespace session
}  // namespace stream
