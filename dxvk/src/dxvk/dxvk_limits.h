#pragma once

#include "dxvk_include.h"

#include "../util/util_env.h"

namespace dxvk {

  enum DxvkLimits : size_t {
    MaxNumRenderTargets         =     8,
    MaxNumVertexAttributes      =    32,
    MaxNumVertexBindings        =    32,
    MaxNumXfbBuffers            =     4,
    MaxNumXfbStreams            =     4,
    MaxNumViewports             =    16,
    MaxNumResourceSlots         =  1216,
    MaxNumActiveBindings        =   384,
    MaxNumQueuedCommandBuffers  =    18,
    MaxNumQueryCountPerPool     =   128,
    MaxNumSpecConstants         =    12,
    MaxUniformBufferSize        = 65536,
    MaxVertexBindingStride      =  2048,
    MaxPushConstantSize         =   128,
  };

  /**
   * \brief Gets the max number of queued command buffers
   *
   * Returns a smaller value on 32-bit platforms to reduce
   * memory pressure from in-flight command buffers.
   * \returns Max number of queued command buffers
   */
  constexpr size_t getMaxQueuedCommandBuffers() {
    return env::is32BitHostPlatform() ? 8 : MaxNumQueuedCommandBuffers;
  }
}
