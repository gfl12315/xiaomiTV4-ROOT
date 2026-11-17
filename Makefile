# 交叉编译（zig cc，无需额外安装工具链；也可替换为 Android NDK 的 clang）
ZIG ?= zig
CFLAGS ?= -O1 -static -Wall

all: gpu_arb_write kfunc su setcap

gpu_arb_write: src/gpu_arb_write.c
	$(ZIG) cc -target arm-linux-musleabihf $(CFLAGS) -o $@ $<

kfunc: src/kfunc.c
	$(ZIG) cc -target aarch64-linux-musl $(CFLAGS) -o $@ $<

su: src/su.c
	$(ZIG) cc -target arm-linux-musleabihf $(CFLAGS) -o $@ $<

setcap: src/setcap.c
	$(ZIG) cc -target arm-linux-musleabihf $(CFLAGS) -o $@ $<

clean:
	rm -f gpu_arb_write kfunc su setcap

.PHONY: all clean
