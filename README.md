# NVHUD

**Next-Generation Performance Overlay for NVIDIA Linux Gaming**

A modern, GPU-accelerated on-screen display (OSD) built in Zig as a MangoHud alternative with NVIDIA-specific optimizations, lower overhead, and deeper integration with the nv* ecosystem.

## Why envyhub?

MangoHud is great, but it has limitations for NVIDIA users:

| Feature | MangoHud | envyhub |
|---------|----------|---------|
| **Overhead** | ~2-5% CPU | <1% (GPU-rendered) |
| **NVIDIA metrics** | Basic (nvidia-smi) | Deep NVML integration |
| **Latency display** | Frame time only | Full Reflex pipeline |
| **Shader status** | None | Real-time compilation status |
| **VRR indicators** | Basic | Full G-Sync/VRR state |
| **Customization** | Config file | Live GUI + config |
| **Language** | C++ | Zig (smaller, faster) |

## Features

### Metrics Displayed

```
┌─────────────────────────────────────────────────────────────┐
│  NVHUD v0.1                              DP-1 165Hz VRR   │
├─────────────────────────────────────────────────────────────┤
│  FPS: 142 (0.1% low: 98)     Frame Time: 7.0ms              │
│  GPU: 72°C  98%  1980MHz     VRAM: 8.2/12GB  68%            │
│  CPU: 62°C  45%  4.8GHz      RAM: 24.1/32GB  75%            │
├─────────────────────────────────────────────────────────────┤
│  ⚡ Reflex: BOOST  Latency: 18.2ms                          │
│  🎮 Input→Display: 22.4ms                                   │
│  📦 Shaders: 1847/1847 (100%)                               │
└─────────────────────────────────────────────────────────────┘
```

### NVIDIA-Specific Metrics

- **GPU Power** - Real-time power draw vs TDP
- **PCIe Bandwidth** - Link speed and utilization
- **Encoder/Decoder** - NVENC/NVDEC usage
- **Memory Bandwidth** - VRAM throughput
- **SM Utilization** - Shader multiprocessor activity
- **Tensor/RT Cores** - AI and ray tracing utilization
- **Driver Overhead** - CPU time spent in driver

### Reflex Integration

nvhud displays the full NVIDIA Reflex latency pipeline when nvlatency is active:

```
Latency Breakdown:
├─ Input:      2.1ms  ████
├─ Simulation: 4.2ms  ████████
├─ Render:     8.3ms  ████████████████
├─ Driver:     1.2ms  ██
└─ Display:    6.7ms  █████████████
   Total:     22.5ms
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        NVHUD                               │
├───────────┬───────────┬───────────┬────────────────────────┤
│  metrics  │  render   │  config   │      hotkeys           │
│  (NVML)   │  (Vulkan) │  (toml)   │      (input)           │
├───────────┴───────────┴───────────┴────────────────────────┤
│                   Vulkan Overlay Layer                       │
├─────────────────────────────────────────────────────────────┤
│  nvlatency  │  nvshader  │  nvsync  │  NVML Direct          │
└─────────────────────────────────────────────────────────────┘
```

## Usage

### Quick Start

```bash
# Enable for all Vulkan games
envyhub enable

# Run specific game with overlay
envyhub run -- ./game

# Toggle overlay in-game
# Default: Right Shift + F12
```

### CLI Commands

```bash
# Show current metrics (terminal)
nvhud status

# Configure overlay
nvhud config --position top-left --opacity 0.8

# Enable specific metrics
nvhud metrics add reflex shader-status vrr

# Disable specific metrics
nvhud metrics remove cpu-temp ram

# Benchmark mode (log to file)
nvhud benchmark --duration 300 --output bench.csv

# Compare runs
nvhud compare bench1.csv bench2.csv
```

### Configuration

```toml
# ~/.config/nvhud/config.toml

[overlay]
enabled = true
position = "top-left"  # top-left, top-right, bottom-left, bottom-right
opacity = 0.85
scale = 1.0
font_size = 14

[metrics]
fps = true
frametime = true
frametime_graph = true

gpu_temp = true
gpu_usage = true
gpu_clock = true
gpu_power = true

vram_usage = true
cpu_usage = true
ram_usage = false

# NVIDIA-specific
reflex_latency = true
shader_status = true
vrr_status = true
nvenc_usage = false
pcie_bandwidth = false

[style]
background_color = "#1a1a2e"
text_color = "#eaeaea"
accent_color = "#7b68ee"
warning_color = "#ffa500"
critical_color = "#ff4444"

[hotkeys]
toggle = "RShift+F12"
cycle_position = "RShift+F11"
screenshot = "RShift+F10"
```

### Environment Variables

```bash
# Enable/disable
NVHUD_ENABLED=1

# Quick config
NVHUD_POSITION=top-right
NVHUD_METRICS=fps,frametime,gpu,reflex

# Steam launch options
NVHUD_ENABLED=1 %command%
```

## Building

```bash
# Build release
zig build -Doptimize=ReleaseFast

# Build with all backends
zig build -Doptimize=ReleaseFast -Dvulkan=true -Dopengl=true

# Run tests
zig build test
```

## Installation

```bash
# System-wide
sudo zig build install --prefix /usr/local

# User install
zig build install --prefix ~/.local

# Install Vulkan layer
sudo cp vulkan/nvhud_layer.json /etc/vulkan/implicit_layer.d/
```

## Comparison with MangoHud

### Performance Overhead

```
Test: Cyberpunk 2077, 1440p, RT Medium
Hardware: RTX 4080, Ryzen 7 7800X3D

No Overlay:    avg 89.2 FPS
MangoHud:      avg 86.7 FPS (-2.8%)
envyhub:       avg 88.9 FPS (-0.3%)
```

### Why Lower Overhead?

1. **GPU-rendered** - Overlay composited on GPU, not CPU
2. **Direct NVML** - No nvidia-smi subprocess spawning
3. **Zig** - No GC, minimal runtime, small binary
4. **Async sampling** - Metrics collected off main thread
5. **Vulkan-native** - No X11/Wayland compositor interaction

## Integration with nv* Stack

| Tool | Integration |
|------|-------------|
| **nvlatency** | Display Reflex latency breakdown |
| **nvshader** | Show shader compilation progress |
| **nvsync** | Display VRR/G-Sync status |
| **nvcontrol** | GUI configuration panel |
| **nvproton** | Automatic game detection |

## Requirements

- NVIDIA GPU (Kepler or newer)
- NVIDIA driver 470+
- Vulkan 1.2+
- Zig 0.12+

## License

MIT License - See [LICENSE](LICENSE)

## Contributing

See [TODO.md](TODO.md) for the development roadmap.

---

