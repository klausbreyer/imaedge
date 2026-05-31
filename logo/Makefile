# imaedge brand asset build
#
# Renders favicon.svg into a set of raster outputs.
#
# Renderer is chosen at runtime:
#   1. qlmanage   macOS Quick Look CLI — uses native WebKit + system fonts,
#                 no extra installs, exact match to the browser preview.
#   2. Chrome     headless fallback for non-macOS (Linux, CI). Detected if
#                 google-chrome / chromium / edge is available on PATH.
#
# Outputs (in $(BUILD)/ — defaults to ./dist/):
#   icon-{16,32,48,64,128,180,192,256,512}.png   transparent square PNG
#   apple-touch-icon.png                          180×180, alias of icon-180
#   favicon.ico                                   16+32+48, needs ImageMagick
#
# Override the renderer explicitly:
#   make build RENDERER=chrome
#   make build RENDERER=qlmanage

BUILD         := dist
SVG_MARK      := favicon.svg
SVG_LOCKUP    := lockup.svg
ICON_SIZES    := 16 32 48 64 128 180 192 256 512
ICON_PNGS     := $(addprefix $(BUILD)/icon-,$(addsuffix .png,$(ICON_SIZES)))
LOCKUP_WIDTHS := 1200 2400
LOCKUP_PNGS   := $(addprefix $(BUILD)/lockup-,$(addsuffix .png,$(LOCKUP_WIDTHS)))

# ---------- renderer detection ----------

QLMANAGE := $(shell command -v qlmanage 2>/dev/null)

CHROME := $(shell \
  for c in \
    google-chrome google-chrome-stable chrome \
    chromium chromium-browser \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  ; do \
    [ -x "$$c" ] 2>/dev/null && { echo "$$c"; exit 0; }; \
    command -v "$$c" >/dev/null 2>&1 && { command -v "$$c"; exit 0; }; \
  done)

# Pick a renderer unless the user pinned one with RENDERER=...
ifeq ($(RENDERER),)
  ifneq ($(QLMANAGE),)
    RENDERER := qlmanage
  else ifneq ($(CHROME),)
    RENDERER := chrome
  endif
endif

MAGICK := $(shell command -v magick 2>/dev/null || command -v convert 2>/dev/null)
CWD    := $(shell pwd)

# ---------- targets ----------

.PHONY: build clean check help
.DEFAULT_GOAL := build

help:
	@echo "imaedge brand build"
	@echo
	@echo "  make build              render all assets into ./$(BUILD)/"
	@echo "  make clean              remove ./$(BUILD)/"
	@echo "  make check              show detected toolchain"
	@echo
	@echo "  RENDERER=qlmanage|chrome   force a specific renderer"

check:
	@echo "  renderer: $(RENDERER)"
	@echo "  qlmanage: $(if $(QLMANAGE),$(QLMANAGE),(not found))"
	@echo "  chrome:   $(if $(CHROME),$(CHROME),(not found))"
	@echo "  magick:   $(if $(MAGICK),$(MAGICK),(not found, .ico will be skipped))"
	@if [ -z "$(RENDERER)" ]; then \
	  echo; echo "ERROR: no renderer available."; \
	  echo "       install Chrome/Chromium, or run on macOS where qlmanage is bundled."; \
	  exit 1; \
	fi

build: check $(ICON_PNGS) $(LOCKUP_PNGS) $(BUILD)/apple-touch-icon.png $(BUILD)/favicon.ico
	@echo
	@echo "built $(BUILD)/:"
	@ls -1 $(BUILD)/

# ---------- renderer: qlmanage ----------
# qlmanage writes to <outdir>/<input>.png, so we rename afterwards.

ifeq ($(RENDERER),qlmanage)
$(BUILD)/icon-%.png: $(SVG_MARK)
	@mkdir -p $(BUILD)
	@echo "  render $@ ($*×$*)"
	@$(QLMANAGE) -t -s $* -o $(BUILD) $(SVG_MARK) >/dev/null 2>&1
	@test -f $(BUILD)/$(SVG_MARK).png || { echo "ERROR: qlmanage produced no thumbnail for size $*"; exit 1; }
	@mv $(BUILD)/$(SVG_MARK).png $@

# qlmanage always produces a square. The lockup is 3:1, so qlmanage renders
# it centred inside an N×N canvas with transparent padding above and below.
# Trim that padding back to the actual content rectangle.
$(BUILD)/lockup-%.png: $(SVG_LOCKUP)
	@mkdir -p $(BUILD)
	@echo "  render $@ (width $*)"
	@$(QLMANAGE) -t -s $* -o $(BUILD) $(SVG_LOCKUP) >/dev/null 2>&1
	@test -f $(BUILD)/$(SVG_LOCKUP).png || { echo "ERROR: qlmanage produced no thumbnail for width $*"; exit 1; }
	@test -n "$(MAGICK)" || { echo "ERROR: ImageMagick is required to crop the lockup"; exit 1; }
	@$(MAGICK) $(BUILD)/$(SVG_LOCKUP).png -bordercolor none -trim +repage $@
	@rm -f $(BUILD)/$(SVG_LOCKUP).png
endif

# ---------- renderer: chrome ----------
# A single render.html wrapper scales the SVG to the viewport; --window-size
# then controls the rasterised dimension exactly.

ifeq ($(RENDERER),chrome)
$(BUILD)/render.html: $(SVG_MARK)
	@mkdir -p $(BUILD)
	@printf '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:transparent}img{display:block;width:100vw;height:100vh}</style><img src="../$(SVG_MARK)" alt="">' > $@

$(BUILD)/icon-%.png: $(BUILD)/render.html $(SVG_MARK)
	@mkdir -p $(BUILD)
	@echo "  render $@ ($*×$*)"
	@"$(CHROME)" \
	  --headless=new --disable-gpu --hide-scrollbars --no-sandbox \
	  --default-background-color=00000000 \
	  --force-device-scale-factor=1 \
	  --window-size=$*,$* \
	  --screenshot="$(CWD)/$@" \
	  "file://$(CWD)/$(BUILD)/render.html" \
	  >/dev/null 2>&1
	@test -f $@ || { echo "ERROR: Chrome did not produce $@"; exit 1; }

$(BUILD)/render-lockup.html: $(SVG_LOCKUP)
	@mkdir -p $(BUILD)
	@printf '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:transparent}img{display:block;width:100vw;height:100vh;object-fit:contain}</style><img src="../$(SVG_LOCKUP)" alt="">' > $@

# Lockup viewBox is 1200×400, so the screenshot window is W × W/3.
$(BUILD)/lockup-%.png: $(BUILD)/render-lockup.html $(SVG_LOCKUP)
	@mkdir -p $(BUILD)
	@echo "  render $@ (width $*)"
	@H=$$(( $* / 3 )); \
	 "$(CHROME)" \
	   --headless=new --disable-gpu --hide-scrollbars --no-sandbox \
	   --default-background-color=00000000 \
	   --force-device-scale-factor=1 \
	   --window-size=$*,$$H \
	   --screenshot="$(CWD)/$@" \
	   "file://$(CWD)/$(BUILD)/render-lockup.html" \
	   >/dev/null 2>&1
	@test -f $@ || { echo "ERROR: Chrome did not produce $@"; exit 1; }
endif

# ---------- derived outputs ----------

$(BUILD)/apple-touch-icon.png: $(BUILD)/icon-180.png
	@cp $< $@
	@echo "  alias  $@"

$(BUILD)/favicon.ico: $(BUILD)/icon-16.png $(BUILD)/icon-32.png $(BUILD)/icon-48.png
	@if [ -n "$(MAGICK)" ]; then \
	  $(MAGICK) $^ $@ && echo "  pack   $@"; \
	else \
	  echo "  skip   $@ (ImageMagick not installed)"; \
	fi

clean:
	rm -rf $(BUILD)
