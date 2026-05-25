# imaedge brand asset build
#
# Renders favicon.svg into a set of raster outputs and copies the source
# SVG into the Phoenix static dir. Sources live next to this Makefile; the
# build output lands in ../static/ and ../static/images/brand/ and is not
# checked into git.
#
# Renderer is chosen at runtime:
#   1. rsvg-convert   librsvg CLI, native SVG transparency, system fonts via
#                     fontconfig. Install on macOS with: brew install librsvg.
#                     Preferred renderer because qlmanage rasterises onto an
#                     opaque white canvas, which leaves a fringe at the
#                     anti-aliased edges of the rounded square.
#   2. qlmanage       macOS Quick Look CLI fallback, white background gets
#                     floodfilled to transparent (leaves edge fringe).
#   3. Chrome         headless fallback for Linux/CI.
#
# Outputs:
#   ../static/favicon.svg                            copy of source
#   ../static/favicon.ico                            16+32+48, needs ImageMagick
#   ../static/apple-touch-icon.png                   180x180, alias of icon-180
#   ../static/images/brand/icon-{16,32,48,64,128,180,192,256,512}.png
#   ../static/images/brand/lockup-{1200,2400}.png
#
# Override the renderer explicitly:
#   make build RENDERER=chrome
#   make build RENDERER=qlmanage

STATIC        := ../static
BRAND_OUT     := $(STATIC)/images/brand
SVG_MARK      := favicon.svg
SVG_LOCKUP    := lockup.svg
ICON_SIZES    := 16 32 48 64 128 180 192 256 512
ICON_PNGS     := $(addprefix $(BRAND_OUT)/icon-,$(addsuffix .png,$(ICON_SIZES)))
LOCKUP_WIDTHS := 1200 2400
LOCKUP_PNGS   := $(addprefix $(BRAND_OUT)/lockup-,$(addsuffix .png,$(LOCKUP_WIDTHS)))

# ---------- renderer detection ----------

RSVG     := $(shell command -v rsvg-convert 2>/dev/null)
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

ifeq ($(RENDERER),)
  ifneq ($(RSVG),)
    RENDERER := rsvg
  else ifneq ($(QLMANAGE),)
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
	@echo "  make build              render all assets into $(STATIC)/ and $(BRAND_OUT)/"
	@echo "  make clean              remove build outputs"
	@echo "  make check              show detected toolchain"
	@echo
	@echo "  RENDERER=qlmanage|chrome   force a specific renderer"

check:
	@echo "  renderer:     $(RENDERER)"
	@echo "  rsvg-convert: $(if $(RSVG),$(RSVG),(not found, install with: brew install librsvg))"
	@echo "  qlmanage:     $(if $(QLMANAGE),$(QLMANAGE),(not found))"
	@echo "  chrome:       $(if $(CHROME),$(CHROME),(not found))"
	@echo "  magick:       $(if $(MAGICK),$(MAGICK),(not found, .ico will be skipped))"
	@if [ -z "$(RENDERER)" ]; then \
	  echo; echo "ERROR: no renderer available."; \
	  echo "       brew install librsvg (preferred), or install Chrome/Chromium."; \
	  exit 1; \
	fi

build: check $(STATIC)/favicon.svg $(ICON_PNGS) $(LOCKUP_PNGS) $(STATIC)/apple-touch-icon.png $(STATIC)/favicon.ico
	@echo
	@echo "built:"
	@ls -1 $(STATIC)/favicon.svg $(STATIC)/favicon.ico $(STATIC)/apple-touch-icon.png 2>/dev/null
	@ls -1 $(BRAND_OUT)/

$(STATIC)/favicon.svg: $(SVG_MARK)
	@mkdir -p $(STATIC)
	@cp $< $@
	@echo "  copy   $@"

# ---------- renderer: qlmanage ----------

# ---------- renderer: rsvg-convert ----------

ifeq ($(RENDERER),rsvg)
$(BRAND_OUT)/icon-%.png: $(SVG_MARK)
	@mkdir -p $(BRAND_OUT)
	@echo "  render $@ ($*x$*)"
	@$(RSVG) -w $* -h $* $(SVG_MARK) -o $@

$(BRAND_OUT)/lockup-%.png: $(SVG_LOCKUP)
	@mkdir -p $(BRAND_OUT)
	@echo "  render $@ (width $*)"
	@$(RSVG) -w $* $(SVG_LOCKUP) -o $@
endif

# ---------- renderer: qlmanage ----------

ifeq ($(RENDERER),qlmanage)
# qlmanage renders against an opaque white canvas. Floodfill white from the
# corner so the area outside the rounded square becomes transparent, while
# the off-white aelig fill (#f6f5f1) inside the mark stays intact.
$(BRAND_OUT)/icon-%.png: $(SVG_MARK)
	@mkdir -p $(BRAND_OUT)
	@echo "  render $@ ($*x$*)"
	@$(QLMANAGE) -t -s $* -o $(BRAND_OUT) $(SVG_MARK) >/dev/null 2>&1
	@test -f $(BRAND_OUT)/$(SVG_MARK).png || { echo "ERROR: qlmanage produced no thumbnail for size $*"; exit 1; }
	@test -n "$(MAGICK)" || { echo "ERROR: ImageMagick is required to floodfill transparency"; exit 1; }
	@$(MAGICK) $(BRAND_OUT)/$(SVG_MARK).png -alpha set -bordercolor white -border 1 -fill none -floodfill +0+0 white -shave 1x1 $@
	@rm -f $(BRAND_OUT)/$(SVG_MARK).png

# qlmanage always produces a square. The lockup is 3:1, so qlmanage renders
# it centred inside an NxN canvas with transparent padding above and below.
# Trim that padding back to the actual content rectangle.
$(BRAND_OUT)/lockup-%.png: $(SVG_LOCKUP)
	@mkdir -p $(BRAND_OUT)
	@echo "  render $@ (width $*)"
	@$(QLMANAGE) -t -s $* -o $(BRAND_OUT) $(SVG_LOCKUP) >/dev/null 2>&1
	@test -f $(BRAND_OUT)/$(SVG_LOCKUP).png || { echo "ERROR: qlmanage produced no thumbnail for width $*"; exit 1; }
	@test -n "$(MAGICK)" || { echo "ERROR: ImageMagick is required to crop the lockup"; exit 1; }
	@$(MAGICK) $(BRAND_OUT)/$(SVG_LOCKUP).png -bordercolor none -trim +repage $@
	@rm -f $(BRAND_OUT)/$(SVG_LOCKUP).png
endif

# ---------- renderer: chrome ----------

ifeq ($(RENDERER),chrome)
$(BRAND_OUT)/render.html: $(SVG_MARK)
	@mkdir -p $(BRAND_OUT)
	@printf '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:transparent}img{display:block;width:100vw;height:100vh}</style><img src="$(CWD)/$(SVG_MARK)" alt="">' > $@

$(BRAND_OUT)/icon-%.png: $(BRAND_OUT)/render.html $(SVG_MARK)
	@mkdir -p $(BRAND_OUT)
	@echo "  render $@ ($*x$*)"
	@"$(CHROME)" \
	  --headless=new --disable-gpu --hide-scrollbars --no-sandbox \
	  --default-background-color=00000000 \
	  --force-device-scale-factor=1 \
	  --window-size=$*,$* \
	  --screenshot="$(CWD)/$@" \
	  "file://$(CWD)/$(BRAND_OUT)/render.html" \
	  >/dev/null 2>&1
	@test -f $@ || { echo "ERROR: Chrome did not produce $@"; exit 1; }

$(BRAND_OUT)/render-lockup.html: $(SVG_LOCKUP)
	@mkdir -p $(BRAND_OUT)
	@printf '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:transparent}img{display:block;width:100vw;height:100vh;object-fit:contain}</style><img src="$(CWD)/$(SVG_LOCKUP)" alt="">' > $@

$(BRAND_OUT)/lockup-%.png: $(BRAND_OUT)/render-lockup.html $(SVG_LOCKUP)
	@mkdir -p $(BRAND_OUT)
	@echo "  render $@ (width $*)"
	@H=$$(( $* / 3 )); \
	 "$(CHROME)" \
	   --headless=new --disable-gpu --hide-scrollbars --no-sandbox \
	   --default-background-color=00000000 \
	   --force-device-scale-factor=1 \
	   --window-size=$*,$$H \
	   --screenshot="$(CWD)/$@" \
	   "file://$(CWD)/$(BRAND_OUT)/render-lockup.html" \
	   >/dev/null 2>&1
	@test -f $@ || { echo "ERROR: Chrome did not produce $@"; exit 1; }
endif

# ---------- derived outputs ----------

$(STATIC)/apple-touch-icon.png: $(BRAND_OUT)/icon-180.png
	@cp $< $@
	@echo "  alias  $@"

$(STATIC)/favicon.ico: $(BRAND_OUT)/icon-16.png $(BRAND_OUT)/icon-32.png $(BRAND_OUT)/icon-48.png
	@if [ -n "$(MAGICK)" ]; then \
	  $(MAGICK) $^ $@ && echo "  pack   $@"; \
	else \
	  echo "  skip   $@ (ImageMagick not installed)"; \
	fi

clean:
	rm -f $(STATIC)/favicon.svg $(STATIC)/favicon.ico $(STATIC)/apple-touch-icon.png
	rm -f $(BRAND_OUT)/icon-*.png $(BRAND_OUT)/lockup-*.png
	rm -f $(BRAND_OUT)/render.html $(BRAND_OUT)/render-lockup.html
