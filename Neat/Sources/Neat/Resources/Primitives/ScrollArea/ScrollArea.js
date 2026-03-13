window.Neat = window.Neat || {};
window.Neat.components = window.Neat.components || {};

window.Neat.components["ScrollArea"] = function (host) {
  if (host.neat && host.neat.scrollArea) {
    return;
  }

  var viewport = host.querySelector(":scope > .scroll-viewport");
  if (!viewport) {
    return;
  }
  var content = viewport.querySelector(":scope > .scroll-content");

  function clamp(val, min, max) {
    return Math.max(min, Math.min(max, val));
  }

  host.neat = host.neat || {};
  host.neat.scrollArea = host.neat.scrollArea || {
    controllers: [],
    interactionCount: 0,
  };

  function setup(axis, visibility) {
    var bar = host.querySelector(":scope > .scroll-bar." + axis);
    if (!bar) {
      return null;
    }
    if (visibility === "never") {
      bar.classList.add("is-hidden");
      return null;
    }
    var track = bar.querySelector(".scroll-track");
    var thumb = bar.querySelector(".scroll-thumb");
    if (!track || !thumb) {
      return null;
    }

    var minThumb = 16;
    var minCompressed = 8;

    var dragging = false;
    var pointerId = null;
    var startPos = 0;
    var startScroll = 0;
    var captureTarget = null;
    var isHovering = false;

    function measure() {
      var scrollSize =
        axis === "vertical" ? viewport.scrollHeight : viewport.scrollWidth;
      var clientSize =
        axis === "vertical" ? viewport.clientHeight : viewport.clientWidth;
      var trackSize =
        axis === "vertical" ? track.clientHeight : track.clientWidth;
      var ratio = clientSize > 0 ? clientSize / scrollSize : 0;
      var rawThumbSize = Math.floor(trackSize * ratio);
      var thumbSize = Math.min(trackSize, Math.max(rawThumbSize, minThumb));
      var maxScroll = Math.max(scrollSize - clientSize, 0);
      var maxThumb = Math.max(trackSize - thumbSize, 0);
      return {
        scrollSize: scrollSize,
        clientSize: clientSize,
        trackSize: trackSize,
        thumbSize: thumbSize,
        maxScroll: maxScroll,
        maxThumb: maxThumb,
      };
    }

    function update() {
      var metrics = measure();
      if (metrics.trackSize <= 0) {
        bar.classList.add("is-hidden");
        return;
      }
      if (visibility === "automatic" || visibility === "hidden") {
        if (metrics.scrollSize <= metrics.clientSize) {
          bar.classList.add("is-hidden");
          return;
        }
        bar.classList.remove("is-hidden");
      } else {
        bar.classList.remove("is-hidden");
      }

      var scrollPos =
        axis === "vertical" ? viewport.scrollTop : viewport.scrollLeft;
      var thumbPos =
        metrics.maxScroll > 0
          ? (scrollPos / metrics.maxScroll) * metrics.maxThumb
          : 0;
      var size = metrics.thumbSize;
      var pos = thumbPos;

      if (thumbPos < 0) {
        size = Math.max(minCompressed, metrics.thumbSize + thumbPos);
        pos = 0;
      } else if (thumbPos > metrics.maxThumb) {
        var overflow = thumbPos - metrics.maxThumb;
        size = Math.max(minCompressed, metrics.thumbSize - overflow);
        pos = metrics.trackSize - size;
      }

      if (axis === "vertical") {
        thumb.style.height = size + "px";
        thumb.style.transform = "translateY(" + pos + "px)";
      } else {
        thumb.style.width = size + "px";
        thumb.style.transform = "translateX(" + pos + "px)";
      }
    }

    function onPointerMove(event) {
      if (!dragging || event.pointerId !== pointerId) {
        return;
      }
      var metrics = measure();
      if (metrics.maxScroll === 0 || metrics.maxThumb === 0) {
        return;
      }

      var currentPos = axis === "vertical" ? event.clientY : event.clientX;
      var delta = currentPos - startPos;
      var scrollDelta = (delta / metrics.maxThumb) * metrics.maxScroll;
      var next = clamp(startScroll + scrollDelta, 0, metrics.maxScroll);
      if (axis === "vertical") {
        viewport.scrollTop = next;
      } else {
        viewport.scrollLeft = next;
      }
    }

    function onPointerUp(event) {
      if (event.pointerId !== pointerId) {
        return;
      }
      dragging = false;
      pointerId = null;
      if (captureTarget && captureTarget.releasePointerCapture) {
        captureTarget.releasePointerCapture(event.pointerId);
      }
      captureTarget = null;
      if (!isHovering) {
        bar.classList.remove("is-expanded");
      }
    }

    function onInteractStart() {
      host.neat.scrollArea.interactionCount += 1;
      host.classList.add("scrollbars-visible");
    }

    function onInteractEnd() {
      host.neat.scrollArea.interactionCount = Math.max(
        0,
        host.neat.scrollArea.interactionCount - 1,
      );
    }


    bar.addEventListener("pointerenter", function () {
      isHovering = true;
      bar.classList.add("is-expanded");
    });
    bar.addEventListener("pointerleave", function () {
      isHovering = false;
      if (!dragging) {
        bar.classList.remove("is-expanded");
      }
    });

    bar.addEventListener(
      "wheel",
      function (event) {
        if (axis === "vertical") {
          viewport.scrollTop += event.deltaY;
        } else {
          viewport.scrollLeft += event.deltaX || event.deltaY;
        }
        event.preventDefault();
      },
      { passive: false },
    );

    thumb.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      onInteractStart();
      dragging = true;
      pointerId = event.pointerId;
      startPos = axis === "vertical" ? event.clientY : event.clientX;
      startScroll =
        axis === "vertical" ? viewport.scrollTop : viewport.scrollLeft;
      captureTarget = thumb;
      thumb.setPointerCapture(event.pointerId);
    });

    thumb.addEventListener("pointermove", onPointerMove);
    thumb.addEventListener("pointerup", function (event) {
      onPointerUp(event);
      onInteractEnd();
    });
    thumb.addEventListener("pointercancel", function (event) {
      onPointerUp(event);
      onInteractEnd();
    });

    track.addEventListener("pointerdown", function (event) {
      if (event.target === thumb) {
        return;
      }
      event.preventDefault();
      onInteractStart();
      dragging = true;
      pointerId = event.pointerId;
      var metrics = measure();
      if (metrics.maxScroll === 0 || metrics.maxThumb === 0) {
        return;
      }
      var rect = track.getBoundingClientRect();
      var clickPos =
        axis === "vertical"
          ? event.clientY - rect.top
          : event.clientX - rect.left;
      var thumbPos = clamp(
        clickPos - metrics.thumbSize / 2,
        0,
        metrics.maxThumb,
      );
      var scrollPos = (thumbPos / metrics.maxThumb) * metrics.maxScroll;
      if (axis === "vertical") {
        viewport.scrollTop = scrollPos;
      } else {
        viewport.scrollLeft = scrollPos;
      }
      startPos = axis === "vertical" ? event.clientY : event.clientX;
      startScroll = scrollPos;
      captureTarget = track;
      track.setPointerCapture(event.pointerId);
    });
    track.addEventListener("pointermove", onPointerMove);
    track.addEventListener("pointerup", function (event) {
      onPointerUp(event);
      onInteractEnd();
    });
    track.addEventListener("pointercancel", function (event) {
      onPointerUp(event);
      onInteractEnd();
    });

    viewport.addEventListener("scroll", update);

    if (typeof ResizeObserver !== "undefined") {
      var observer = new ResizeObserver(update);
      observer.observe(viewport);
      if (content) {
        observer.observe(content);
      }
    } else {
      window.addEventListener("resize", update);
    }

    update();

    return { update: update };
  }

  var axis = host.getAttribute("data-axis") || "vertical";
  var visibility =
    host.getAttribute("data-scrollbar-visibility") || "automatic";
  var behavior = host.getAttribute("data-scrollbar-behavior") || "mouseMove";
  var controllers = [];
  if (axis === "vertical" || axis === "both") {
    var v = setup("vertical", visibility);
    if (v) {
      controllers.push(v);
    }
  }
  if (axis === "horizontal" || axis === "both") {
    var h = setup("horizontal", visibility);
    if (h) {
      controllers.push(h);
    }
  }

  host.neat.scrollArea.controllers = controllers;

  if (visibility === "hidden") {
    var hideTimeout = null;
    var hoverCount = 0;

    function showBars() {
      host.classList.add("scrollbars-visible");
      if (hideTimeout) {
        clearTimeout(hideTimeout);
        hideTimeout = null;
      }
    }

    function scheduleHide() {
      if (hideTimeout) {
        clearTimeout(hideTimeout);
      }
      hideTimeout = setTimeout(function () {
        if (
          host.neat &&
          host.neat.scrollArea &&
          (host.neat.scrollArea.interactionCount > 0 || hoverCount > 0)
        ) {
          scheduleHide();
          return;
        }
        host.classList.remove("scrollbars-visible");
      }, 900);
    }

    var bars = host.querySelectorAll(":scope > .scroll-bar");
    bars.forEach(function (bar) {
      bar.addEventListener("pointerenter", function () {
        hoverCount += 1;
        showBars();
      });
      bar.addEventListener("pointerleave", function () {
        hoverCount = Math.max(0, hoverCount - 1);
        scheduleHide();
      });
    });

    if (behavior === "mouseMove") {
      host.addEventListener("pointerenter", function () {
        showBars();
      });
      host.addEventListener("pointermove", function () {
        showBars();
        scheduleHide();
      });
      host.addEventListener("pointerleave", function () {
        scheduleHide();
      });
    }
    viewport.addEventListener("scroll", function () {
      showBars();
      scheduleHide();
    });

    scheduleHide();
  }
};
