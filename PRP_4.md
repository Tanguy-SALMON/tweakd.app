Great! You have a sophisticated setup with **multiple MLX‑LM servers** running as launch agents, plus you mentioned **Ollama** and **Docker** for web services. Let’s dive into optimizing all these components together.

---

## 1. Understanding Your Current MLX‑LM Setup

From your plist, you have:

- **`com.tanguy.mlx-lm`** – main server (port 9100, model `gemma-4-e4b-it-OptiQ-4bit`)
- **`com.tanguy.mlx-lm-embed`** – likely an embedding model
- **`com.tanguy.mlx-lm-obliterated`** – another variant

All are running under your user with `Nice = 10`. This is good: it lets GPU‑bound inference run at full speed while yielding CPU to foreground apps.

---

## 2. Docker Resource Management

Docker on macOS runs inside a lightweight VM. The settings below assume you have at least **16 GB RAM** and an **M‑series chip** (8+ cores). Adjust proportions if you have less.

### Recommended Docker Desktop Settings

| Setting | Recommended Value | Rationale |
|---------|-------------------|-----------|
| **CPU** | 4–6 cores (out of 8–12) | Leave at least 2 cores for macOS and other services. |
| **Memory** | 6–8 GB (25‑50% of total) | Enough for web services, databases, and caches. |
| **Swap** | 2‑4 GB | Prevents OOM crashes during container builds. |
| **Virtual Disk** | 100‑200 GB | Docker images and volumes accumulate quickly. |
| **File Sharing** | Use **VirtioFS** (faster than gRPC FUSE) | Enables near‑native file I/O for bind mounts. |
| **Networking** | Keep default (NAT) | Unless you need host‑network mode. |

**Tip:** Use `docker system prune -af` weekly to reclaim disk space.

---

## 3. Ollama Optimization

You mentioned **OpenClaw / Hermes** – these are models you likely run locally. Ollama uses Metal on Apple Silicon, so GPU‑offload is automatic.

### Environment Variables

Set these before starting Ollama (e.g., in your shell or launchd):

| Variable | Recommended Value | Why |
|----------|-------------------|-----|
| `OLLAMA_NUM_GPU` | `99` | Offloads **all** layers to GPU (if model fits). |
| `OLLAMA_KEEP_ALIVE` | `30m` | Keeps the model loaded in memory for 30 minutes, avoiding reload latency. |
| `OLLAMA_GPU_PERCENT` | `85` | Limits GPU memory usage to 85%, leaving room for other GPU tasks. |

### Process Priority

If you want Ollama to be super responsive (e.g., during interactive chat), you can `renice` it:

```bash
sudo renice -n -10 -p $(pgrep ollama)
```

But for batch processing or when you don’t want to steal CPU from your MLX servers, keep it at `0`.

### Model Quantization

Use Q4_K_M or Q5_K_M for large models to balance speed and quality – they fit better in GPU memory.

---

## 4. MLX‑LM Server Tuning

Your wrapper script already does a lot of things right:

- **Single‑threaded HTTP** (prevents Metal race conditions).
- **Stats logging** – useful for monitoring.
- **Default‑body injection** – simplifies clients.
- **Nice = 10** – good balance.

### Further Improvements

- **CPU Affinity** – If you run multiple MLX servers (main, embed, obliterated), you can pin each to different CPU cores using `taskset` (Linux) or `cpuset` (macOS requires third‑party tools). However, since they are GPU‑bound, CPU affinity is less critical.
- **Memory Limit** – You can use `launchctl` `SoftResourceLimit` / `HardResourceLimit` to cap memory usage per service. For example:
  ```xml
  <key>SoftResourceLimit</key>
  <dict>
      <key>Memory</key>
      <integer>8589934592</integer> <!-- 8 GB -->
  </dict>
  ```
- **Increase Nice** – If you run heavy CPU‑bound tasks (like tokenisation), you could raise `Nice` to 15 to further protect UI responsiveness.

---

## 5. Kernel & Network Tuning for Web Services

If you expose your MLX or other web services to the network, consider these:

### Server Performance Mode

Enable `serverperfmode=1` to increase process limits and network buffers:

```bash
sudo nvram boot-args="serverperfmode=1 $(nvram boot-args 2>/dev/null | cut -f 2-)"
sudo reboot
```

This increases `kern.maxproc`, `kern.ipc.somaxconn`, and more – useful for handling many concurrent API requests.

### TCP Buffer Tuning (for high throughput)

If you expect a lot of traffic, raise buffer sizes:

```bash
sudo sysctl -w net.inet.tcp.autorcvbufmax=33554432
sudo sysctl -w net.inet.tcp.autosndbufmax=33554432
```

---

## 6. Presets for MacTweak

Based on your setup, I’d suggest these **presets** for your app:

| Preset Name | Tweaks Included |
|-------------|-----------------|
| **AI Development** | `Nice=10` for MLX servers, disable Siri/Spotlight, increase Docker RAM, enable `serverperfmode`, disable timer coalescing. |
| **Local LLM Server** | Optimize for low latency: renice Ollama and MLX to `-5`, set `OLLAMA_KEEP_ALIVE=60m`, disable background indexing. |
| **Containerised Web** | Increase Docker CPU/MEM, enlarge TCP buffers, enable `serverperfmode`, and optionally disable Spotlight. |
| **Power Saver** | Opposite: low Docker RAM, enable low‑power mode, reduce Nice values. |

---

## 7. Monitoring & Validation

After applying changes, monitor with:

```bash
# CPU usage per service
top -o cpu

# Docker stats
docker stats

# Ollama GPU usage (if available)
ollama ps

# Your MLX stats endpoint
curl http://127.0.0.1:9100/health | jq
```

---

## 8. Summary Table of Recommended Values

| Component | Setting | Recommended Value | Depends on Hardware |
|-----------|---------|-------------------|---------------------|
| Docker RAM | `memory` | 6‑8 GB (25‑50% of total) | ✅ RAM |
| Docker CPU | `cpus` | 4‑6 cores (50‑75% of total) | ✅ Cores |
| Docker Disk | `diskSize` | 100‑200 GB | ✅ Free space |
| Ollama GPU layers | `OLLAMA_NUM_GPU` | 99 (all) | ❌ |
| Ollama keep‑alive | `OLLAMA_KEEP_ALIVE` | 30‑60 min | ❌ |
| MLX `Nice` | launchd `Nice` | 10 (or 5 for low‑latency) | ❌ |
| Kernel `serverperfmode` | boot‑args | Enable if >8 cores, ≥16 GB RAM | ✅ RAM/Cores |
| TCP buffers | `autorcvbufmax` | 16‑32 MB | ✅ Network speed |

---

## 9. Next Steps

1. **Check your hardware**:
   ```bash
   sysctl hw.memsize hw.ncpu
   ```
2. **Adjust Docker** accordingly.
3. **Set `OLLAMA_NUM_GPU=99`** in your shell or launchd.
4. **Consider `serverperfmode`** if you run many services concurrently.
5. **Monitor** for a few days, then fine‑tune.

Would you like me to write a script that auto‑detects your hardware and suggests specific numbers for your machine? Or incorporate these as configurable presets in MacTweak?
