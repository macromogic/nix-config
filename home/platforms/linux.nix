# Non-NixOS Linux dev servers.
{ ... }:

{
  targets.genericLinux.enable = true;
  # GPU drivers (CUDA included) stay with the host, never managed here; this
  # would otherwise ask for a root-installed /run/opengl-driver setup.
  targets.genericLinux.gpu.enable = false;
}
