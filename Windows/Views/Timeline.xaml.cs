using CyteEncoder;
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using Windows.Media.Core;
using Microsoft.UI.Xaml;
using Windows.UI;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml.Shapes;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Foundation;
using System.Collections.Generic;
using Windows.Media.Editing;
using Windows.Media.Ocr;

namespace Cyte
{
    public sealed class AppInterval: INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        private static OcrEngine engine = OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en"));

        public StorageFile file { get; internal set; }
        public MediaSource media { get; internal set; }
        public string title { get; internal set; }
        public string bundle { get; internal set; }
        public DateTime start { get; internal set; }
        public DateTime end { get; internal set; }
        public bool save { get; internal set; }
        public double length { get; internal set; }
        public double offset { get; internal set; }
        public BitmapImage bundleThumbnail { get; internal set; } = new BitmapImage();
        public Color color { get; internal set; } = Colors.Gray;
        public Episode episode;

        public BitmapImage thumbnail { get; internal set; } = new BitmapImage();
        public List<Rect> highlight { get; internal set; } = new List<Rect>();
        public AppInterval(Episode _episode)
        {
            
            title = _episode.title;

            start = DateTime.FromFileTime(_episode.start);
            end = DateTime.FromFileTime(_episode.end);
            save = _episode.save;
            bundle = _episode.bundle;

            episode = _episode;
        }

        public async void UpdateThumb(double offset, string snippet)
        {
            var filepath = $"{Memory.PathForEpisode(episode.start)}\\{title}.mov";
            Debug.WriteLine(filepath);
            file = await Windows.Storage.StorageFile.GetFileFromPathAsync(filepath);
            MediaComposition mediaComposition = new MediaComposition();
            var videoFile = await MediaClip.CreateFromFileAsync(file);
            mediaComposition.Clips.Add(videoFile);
            // @todo use natural frame size for best results
            var thumb = await mediaComposition.GetThumbnailAsync(TimeSpan.FromSeconds(offset), 1920, 1080, VideoFramePrecision.NearestFrame);
            thumbnail.SetSource(thumb);

            var bitmap = await BitmapDecoder.CreateAsync(thumb);
            var softwareBitmap = await bitmap.GetSoftwareBitmapAsync();
            OcrResult ocrResults = await engine.RecognizeAsync(softwareBitmap);
            highlight.Clear();
            foreach (var line in ocrResults.Lines)
            {
                foreach(var word in line.Words)
                {
                    Debug.WriteLine(word.Text);
                    if(word.Text.ToLower().Contains(snippet.ToLower()))
                    {
                        highlight.Add(word.BoundingRect);
                    }
                }
            }
        }

        public async Task<bool> Update()
        {
            try
            {
                var filepath = $"{Memory.PathForEpisode(episode.start)}\\{title}.mov";
                Debug.WriteLine(filepath);
                file = await Windows.Storage.StorageFile.GetFileFromPathAsync(filepath);
                media = MediaSource.CreateFromStorageFile(file);

                filepath = System.IO.Path.Combine(Memory.HomeDirectory(), "Icons", $"{Memory.RemoveInvalid(bundle)}.png");
                file = await Windows.Storage.StorageFile.GetFileFromPathAsync(filepath);
                var stream = await file.OpenReadAsync();
                var bitmap = await BitmapDecoder.CreateAsync(stream);
                var pixelProvider = await bitmap.GetPixelDataAsync();
                var pixels = pixelProvider.DetachPixelData();
                bundleThumbnail = new BitmapImage(new Uri(filepath));

                int red = 0, green = 0, blue = 0;

                for (int i = 0; i < pixels.Length; i += 4)
                {
                    red += pixels[i];
                    green += pixels[i + 1];
                    blue += pixels[i + 2];
                }

                int pixelCount = pixels.Length / 4;
                byte averageRed = (byte)(red / pixelCount);
                byte averageGreen = (byte)(green / pixelCount);
                byte averageBlue = (byte)(blue / pixelCount);

                color = Color.FromArgb(255, averageRed, averageGreen, averageBlue);

            }
            catch { }
            return true;
        }

    }

    public class TimelineArgs
    {
        public string filter { get; }
        public AppInterval[] intervals { get; }
        public double offset { get; }

        public TimelineArgs(string _filter, AppInterval[] _intervals, double _offset) 
        { 
            filter = _filter;
            intervals = _intervals;
            offset = _offset;
        }
    }
    public sealed partial class Timeline : Page, INotifyPropertyChanged
    {
        public TimelineArgs options { get; internal  set; }
        //public IMediaPlaybackSource media { get; internal set; } = null;
        public static int windowLengthInSeconds = 60 * 2;
        public string currentTime { get; internal set; } = "";
        public string readableOffset { get; internal set; } = "";
        public double secondsOffsetFromLastEpisode { get; set; } = 0.0;
        public double lastX { get; set; } = 0.0;
        public bool isDragging { get; set; } = false;
        public long currentStart = 0;

        public event PropertyChangedEventHandler PropertyChanged;

        public Timeline()
        {
            InitializeComponent();
        }

        public (AppInterval, double) activeInterval(double at)
        {
            var offset_sum = 0.0;
            AppInterval select = null;
            foreach(var interval in options.intervals)
            {
                var next_offset = offset_sum + interval.length;
                bool is_within = (offset_sum <= at && next_offset >= at);
                offset_sum = next_offset;
                if (is_within)
                {
                    select = interval;
                    break;
                }
            }
            return (select, offset_sum);
        }

        public double startTimeForEpisode(AppInterval interval)
        {
            var start = Math.Max(secondsOffsetFromLastEpisode + Timeline.windowLengthInSeconds - interval.offset - interval.length, 0.0);
            return start;
        }

        public double endTimeForEpisode(AppInterval interval)
        {
            var end = Math.Min(Timeline.windowLengthInSeconds, secondsOffsetFromLastEpisode + Timeline.windowLengthInSeconds - interval.offset);
            return end;
        }

        public double windowOffsetToCenter(AppInterval of)
        {
            double interval_center = ( startTimeForEpisode(of) + endTimeForEpisode(of) ) / 2.0;
            return interval_center / Timeline.windowLengthInSeconds;
        }

        protected async override void OnNavigatedTo(NavigationEventArgs e)
        {
            // get the selected episode, calculate offset..
            options = (TimelineArgs)e.Parameter;
            if (options.intervals.Length > 0 )
            {
                secondsOffsetFromLastEpisode = options.offset;
                var interval = activeInterval(options.offset);
                var filepath = $"{Memory.PathForEpisode(interval.Item1.episode.start)}\\{interval.Item1.title}.mov";
                Debug.WriteLine(filepath);
                var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(filepath);
                mediaPlayer.MediaPlayer.SetFileSource(file);
                currentStart = options.intervals[0].episode.start;
                currentTime = options.intervals[0].start.ToString();
            }
            UpdateData();
            MainWindow.self.BackButton.Visibility = Visibility.Visible;
            base.OnNavigatedTo(e);
        }

        private void StackPanel_PointerEntered(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
        {
            isDragging = true;
        }

        private void StackPanel_PointerExited(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
        {
            isDragging = false;
        }

        private async void UpdateData()
        {
            var active = activeInterval(secondsOffsetFromLastEpisode);
            if (active.Item1 == null)
            {
                return;
            }
            if (currentStart != active.Item1.episode.start)
            {
                var filepath = $"{Memory.PathForEpisode(active.Item1.episode.start)}\\{active.Item1.title}.mov";
                Debug.WriteLine(filepath);
                var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(filepath);
                mediaPlayer.MediaPlayer.SetFileSource(file);
                currentStart = active.Item1.episode.start;
            }
            Debug.WriteLine(secondsOffsetFromLastEpisode);

            mediaPlayer.MediaPlayer.PlaybackSession.Position = TimeSpan.FromSeconds(active.Item2 - secondsOffsetFromLastEpisode);
            mediaPlayer.Width = MainWindow.WindowSize.Width - 340;
            //mediaPlayer.InvalidateArrange();
            slider.Children.Clear();
            var width = MainWindow.WindowSize.Width;
            double pixelsPerSecond = width / windowLengthInSeconds;
            foreach (var interval in options.intervals)
            {
                var start = startTimeForEpisode(interval);
                var end = endTimeForEpisode(interval);
                if( start <= Timeline.windowLengthInSeconds && end >= 0)
                {
                    Debug.WriteLine($"Timeline: {start} - {end}");

                    var rect = new Rectangle
                    {
                        Name = "myRectangle" + start,
                        Fill = new SolidColorBrush(interval.color),
                        Width = (end - start) * pixelsPerSecond,
                        Height = 24,
                        Margin = new Thickness(0),
                        RadiusX = 12,
                        RadiusY = 12
                    };
                    Canvas.SetLeft(rect, start * pixelsPerSecond);
                    Canvas.SetZIndex(rect, 0);
                    slider.Children.Add(rect);
                    Image img = new Image();
                    img.Source = interval.bundleThumbnail;
                    img.Width = 16;
                    img.Height = 16;
                    img.Margin = new Thickness(4);
                    Canvas.SetLeft(img, (((end-start) * 0.5) + start) * pixelsPerSecond - 12);
                    Canvas.SetZIndex(img, 20);
                    slider.Children.Add(img);
                }
            }

            currentTime = active.Item1.start.AddSeconds(active.Item2 - secondsOffsetFromLastEpisode).ToString("MM/dd/yyyy, HH:mm:ss");
            double progress = active.Item2 - secondsOffsetFromLastEpisode;
            var anchor = DateTime.Now.ToFileTimeUtc() - active.Item1.end.ToFileTimeUtc();
            double seconds = Math.Max(1.0, anchor -  progress) * 0.0000001;
            readableOffset = $"{MainPage.SecondsToReadable(seconds)} ago";
            Debug.WriteLine(currentTime);
            //active.Item1.UpdateThumb(progress, options.filter);
        }

        private void StackPanel_PointerMoved(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
        {
            if( isDragging)
            {
                var pos = e.GetCurrentPoint((Microsoft.UI.Xaml.UIElement)sender).Position;
                Debug.WriteLine(pos.ToString());

                double delta = (pos.X - lastX) * 0.5;
                lastX = pos.X;
                double newStart = secondsOffsetFromLastEpisode + delta;
                var end = (options.intervals.LastOrDefault().offset + options.intervals.LastOrDefault().length);
                if (newStart > 0 && newStart < end)
                {
                    secondsOffsetFromLastEpisode = newStart;
                }
                UpdateData();
                PropertyChanged(this, new PropertyChangedEventArgs("mediaPlayer"));
                PropertyChanged(this, new PropertyChangedEventArgs("currentTime"));
                PropertyChanged(this, new PropertyChangedEventArgs("readableOffset"));
                PropertyChanged(this, new PropertyChangedEventArgs("cvsIntervals"));
            }
        }
    }
}
