export type RangeWebGLContext = WebGLRenderingContext | WebGL2RenderingContext;

export function hasDrawableWebGLSurface(
  canvas: HTMLCanvasElement,
  context: RangeWebGLContext,
) {
  return canvas.isConnected
    && canvas.width > 0
    && canvas.height > 0
    && context.drawingBufferWidth > 0
    && context.drawingBufferHeight > 0
    && !context.isContextLost();
}

export function hasCompleteFramebuffer(
  context: RangeWebGLContext,
  framebuffer: WebGLFramebuffer,
) {
  context.bindFramebuffer(context.FRAMEBUFFER, framebuffer);
  return context.checkFramebufferStatus(context.FRAMEBUFFER)
    === context.FRAMEBUFFER_COMPLETE;
}
