# Maintainer: GhostKellz <ghost@ghostkellz.sh>
pkgname=nvhud
pkgver=1.0.0
pkgrel=1
pkgdesc="NVIDIA GPU Performance Overlay - Vulkan layer with FPS, temps, and metrics"
arch=('x86_64')
url="https://github.com/ghostkellz/nvhud"
license=('MIT')
depends=('glibc' 'vulkan-icd-loader')
makedepends=('zig>=0.14' 'glslang')
optdepends=(
    'nvidia-utils: NVML GPU metrics (temp, usage, clocks, power)'
)
provides=('nvhud')
install=nvhud.install
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    zig build -Doptimize=ReleaseFast
}

package() {
    cd "$pkgname-$pkgver"

    # CLI binary
    install -Dm755 zig-out/bin/nvhud "$pkgdir/usr/bin/nvhud"

    # Vulkan layer library
    install -Dm755 zig-out/lib/libVkLayer_nvhud.so "$pkgdir/usr/lib/libVkLayer_nvhud.so"

    # Layer manifest (implicit layer - loads automatically when NVHUD=1)
    # Uses nvhud_layer_system.json which has /usr/lib path hardcoded
    install -Dm644 nvhud_layer_system.json \
        "$pkgdir/usr/share/vulkan/implicit_layer.d/nvhud_layer.json"

    # Documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
