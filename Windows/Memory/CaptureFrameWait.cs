using Microsoft.Graphics.Canvas;
using System;
using System.Threading;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace CyteEncoder
{
    public sealed class SurfaceWithInfo : IDisposable
    {
        public IDirect3DSurface Surface { get; internal set; }
        public TimeSpan SystemRelativeTime { get; internal set; }

        public void Dispose()
        {
            Surface?.Dispose();
            Surface = null;
        }
    }

    public sealed class CaptureFrameWait : IDisposable
    {
        public CaptureFrameWait(
            GraphicsCaptureItem item,
            SizeInt32 size,
            bool includeCursor)
        {
            _device = new CanvasDevice();
            _item = item;
            _frameEvent = new ManualResetEvent(false);
            _closedEvent = new ManualResetEvent(false);
            _events = new[] { _closedEvent, _frameEvent };

            InitializeCapture(size, includeCursor);
        }

        private void InitializeCapture(SizeInt32 size, bool includeCursor)
        {
            _item.Closed += OnClosed;
            _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
                _device,
                DirectXPixelFormat.B8G8R8A8UIntNormalized,
                1,
                size);
            _framePool.FrameArrived += OnFrameArrived;
            _session = _framePool.CreateCaptureSession(_item);
            if (!includeCursor)
            {
                _session.IsCursorCaptureEnabled = includeCursor;
            }
            _session.StartCapture();
        }

        private void SetResult(Direct3D11CaptureFrame frame)
        {
            _currentFrame = frame;
            _frameEvent.Set();
        }

        private void Stop()
        {
            _closedEvent.Set();
        }

        private void OnFrameArrived(Direct3D11CaptureFramePool sender, object args)
        {
            SetResult(sender.TryGetNextFrame());
        }

        private void OnClosed(GraphicsCaptureItem sender, object args)
        {
            Stop();
        }

        private void Cleanup()
        {
            _framePool?.Dispose();
            _session?.Dispose();
            if (_item != null)
            {
                _item.Closed -= OnClosed;
            }
            _item = null;
            _device = null;
            _currentFrame?.Dispose();
        }

        public SurfaceWithInfo WaitForNewFrame()
        {
            // Let's get a fresh one.
            _currentFrame?.Dispose();
            _frameEvent.Reset();

            var signaledEvent = _events[WaitHandle.WaitAny(_events)];
            if (signaledEvent == _closedEvent)
            {
                Cleanup();
                return null;
            }

            var result = new SurfaceWithInfo();
            result.SystemRelativeTime = _currentFrame.SystemRelativeTime;

            result.Surface = _currentFrame.Surface;
            return result;
        }

        public void Dispose()
        {
            Stop();
            Cleanup();
        }

        private CanvasDevice _device;
        private ManualResetEvent[] _events;
        private ManualResetEvent _frameEvent;
        private ManualResetEvent _closedEvent;
        private Direct3D11CaptureFrame _currentFrame;

        private GraphicsCaptureItem _item;
        private GraphicsCaptureSession _session;
        private Direct3D11CaptureFramePool _framePool;
    }
}
