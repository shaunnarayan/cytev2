using CyteEncoder;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using Windows.Graphics.Capture;
using Windows.Graphics.Display;
using Windows.Security.Authorization.AppCapabilityAccess;
using Windows.UI.Popups;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Linq;
using Windows.System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml.Data;
using Windows.Media.Editing;
using System.IO;
using Windows.Foundation;
using Windows.Media.Transcoding;
using Microsoft.UI.Xaml.Navigation;

namespace Cyte
{
    public class BoolToValueConverter<T> : IValueConverter
    {
        public T FalseValue { get; set; }
        public T TrueValue { get; set; }

        public object Convert(object value, Type targetType, object parameter, string culture)
        {
            if (value == null)
                return FalseValue;
            else
                return (bool)value ? TrueValue : FalseValue;
        }

        public object ConvertBack(object value, Type targetType, object parameter, string culture)
        {
            return value != null ? value.Equals(TrueValue) : false;
        }
    }
    public class BoolToStringConverter : BoolToValueConverter<String> { }

    public sealed partial class MainPage : Page, INotifyPropertyChanged
    {
        [DllImport("user32.dll")]
        static extern IntPtr GetForegroundWindow();
        public static MainPage self { get; private set; }

        private Episode[] _episodes;
        private List<AppInterval> episodes = new List<AppInterval>();
        public BundleExclusion[] bundleExclusions { get; set; }
        public Visibility showAdvanced { get; internal set; }
        public Visibility showTimelapse { get; internal set; } = Visibility.Collapsed;
        public bool showFaves { get; internal set; }
        public string filter { get; internal set; } = "";
        public event PropertyChangedEventHandler PropertyChanged;
        public string highlightedBundle { get; internal set; } = string.Empty;
        public DateTimeOffset start { get; internal set; } = DateTime.Now.AddMonths(-1);
        public DateTimeOffset end { get; internal set; } = DateTime.Now;
        public double episodesLengthSum = 0.0;
        public string totalTimeShown { get; internal set; } = "";
        public Interval[] _intervals { get; internal set; }
        private bool isChatSetup = false;
        public MainPage()
        {
            showAdvanced = Visibility.Collapsed;
            showFaves = false;
            InitializeComponent();
            self = this;

                /*
                   TODO UA315_A Use Microsoft.UI.Windowing.AppWindow for window Management instead of ApplicationView/CoreWindow or Microsoft.UI.Windowing.AppWindow APIs
                   Read: https://docs.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/guides/windowing
                */
                //ApplicationView.GetForCurrentView().SetPreferredMinSize( new Size(539, 285));

            if (!GraphicsCaptureSession.IsSupported())
            {
                IsEnabled = false;

                var dialog = new MessageDialog(
                    "Screen capture is not supported on this device for this release of Windows!",
                    "Screen capture unsupported");
                
                var ignored = dialog.ShowAsync();
                return;
            }
            var vault = new Windows.Security.Credentials.PasswordVault();
            var passwords = vault.RetrieveAll();
            if (passwords.Count > 0)
            {
                searchTextBox.PlaceholderText = "Search or chat your history";
                isChatSetup = true;
            }
            progressBar.Visibility = Visibility.Collapsed;
            startDatePicker.Date = start;
            endDatePicker.Date = end;
        }

        public async Task RefreshData()
        {
            if(filter.EndsWith("?"))
            {   //Don't update for chat
                return;
            }
            if (filter.Length < 3)
            {
                string predicate = $" WHERE start >= {start.DateTime.ToFileTimeUtc()} AND end <= {end.DateTime.ToFileTimeUtc()}";
                if(showFaves)
                {
                    predicate += " AND save == 1";
                }
                if(highlightedBundle.Length > 0 )
                {
                    predicate += $" AND bundle == '{highlightedBundle}'";
                }
                _episodes = Episode.GetList(predicate, " LIMIT 32");
            }
            else
            {
                List<Episode> eps = new List<Episode>();
                _intervals = Memory.Instance.Search(filter).Where(interval =>
                {
                    if( interval.episode == null)
                    {
                        return false;
                    }
                    if(showFaves && interval.episode.save != true)
                    {
                        return false;
                    }
                    if(highlightedBundle.Length != 0 && interval.episode.bundle != highlightedBundle) 
                    {
                        return false;
                    }
                    bool is_within = (interval.episode.start >= start.DateTime.ToFileTimeUtc()) && (interval.episode.end <= end.DateTime.ToFileTimeUtc());
                    if( is_within && !eps.Contains(interval.episode))
                    {
                        eps.Add(interval.episode);
                    }
                    return is_within;
                }).ToArray();
                _episodes = eps.ToArray();
            }

            foreach (var episode in episodes)
            {
                episode.Dispose();
            }
            episodes = new List<AppInterval>();
            var offset = 0.0;
            foreach (var episode in _episodes)
            {
                var length = (episode.end - episode.start) * 0.0000001;
                var interval = new AppInterval(episode);
                interval.offset = offset;
                interval.length = length;
                await interval.Update();
                episodes.Add(interval);
                offset += length;
            }
            episodesLengthSum = offset;
            showTimelapse = episodesLengthSum < (60 * 60 * 10) ? Visibility.Visible : Visibility.Collapsed;
            totalTimeShown = SecondsToReadable(episodesLengthSum);
            cvsEpisodes.Source = episodes;

            bundleExclusions = BundleExclusion.GetList();
            var exclusions = new List<CyteBundleExclusion>();
            foreach (var exclusion in bundleExclusions)
            {
                var ex = new CyteBundleExclusion(exclusion);
                ex.Update();
                exclusions.Add(ex);
            }
            cvsBundles.Source = exclusions;


            PropertyChanged(this, new PropertyChangedEventArgs("showTimelapse"));
            PropertyChanged(this, new PropertyChangedEventArgs("totalTimeShown"));
            PropertyChanged(this, new PropertyChangedEventArgs("cvsEpisodes"));
            PropertyChanged(this, new PropertyChangedEventArgs("cvsBundles"));
        }

        protected async override void OnNavigatedTo(NavigationEventArgs e)
        {
            await RefreshData();
            base.OnNavigatedTo(e);
        }

        public static string SecondsToReadable(double seconds)
        {
            double hr = seconds / 3600;
            int days = (int)(hr / 24);
            hr -= days * 24;
            int min = (int)(seconds / 60 % 60);
            int sec = (int)(seconds % 60);

            var res = "";
            if (days > 0)
            {
                res += $"{days} days, ";
            }
            if (hr > 0)
            {
                res += $"{(int)hr} hours, ";
            }
            if (min > 0)
            {
                res += $"{min} minutes, ";
            }
            res += $"{sec} seconds";
            return res;
        }

        private void ToggleAdvanced(object sender, RoutedEventArgs e)
        {
            showAdvanced = (showAdvanced == Visibility.Collapsed) ? Visibility.Visible : Visibility.Collapsed;
            PropertyChanged(this, new PropertyChangedEventArgs("showAdvanced"));
        }

        private async void ToggleFaves(object sender, RoutedEventArgs e)
        {
            showFaves = !showFaves;
            await RefreshData();
            PropertyChanged(this, new PropertyChangedEventArgs("showFaves"));
        }

        private void OpenSettings(object sender, RoutedEventArgs e)
        {
            Frame.Navigate(typeof(Settings));
        }

        private async void Refresh(object sender, RoutedEventArgs e)
        {
            end = DateTime.Now;
            endDatePicker.Date = end;
            showFaves = false;
            highlightedBundle = "";
            await RefreshData();
        }

        private async void Search(object sender, RoutedEventArgs e)
        {
            // run search with filter (or chat)
            filter = searchTextBox.Text;
            Debug.WriteLine(filter);
            if (isChatSetup && filter.EndsWith("?")) 
            { 
                // run through agent
                ChatArgs args = new ChatArgs(filter, _intervals);
                Frame.Navigate(typeof(Chat), args);

                filter = "";
            }
            else
            {
                await RefreshData();
            }
        }

        private async void StarEpisode(object sender, RoutedEventArgs e)
        {
            // Star the ep
            DateTime epStart = (DateTime) ((Button)sender).Tag;
            var find = _episodes.Where(ep =>
            {
                return ep.start == epStart.ToFileTimeUtc();
            });
            if( find.Count() > 0 )
            {
                var ep = find.First();
                ep.save = !ep.save;
                ep.Save();
            }
            await RefreshData();
        }

        private double offsetForEpisode(AppInterval episode)
        {
            var offset_sum = 0.0;
            foreach (var interval in episodes)
            {
                offset_sum += interval.length;
                if(interval.start == episode.start)
                {
                    break;
                }
            }
            return offset_sum;
        }

        private void OpenEpisode(object sender, RoutedEventArgs e)
        {
            // Navigate to timeline centered at tag
            var epStart = (DateTime) ((Button)sender).Tag;
            var find = episodes.Where(ep =>
            {
                return ep.start.ToFileTimeUtc() == epStart.ToFileTimeUtc();
            });
            var offset = 0.0;
            if (find.Count() > 0)
            {
                offset = offsetForEpisode(find.First());
            }
            foreach (var episode in episodes)
            {
                episode.Dispose();
            }
            cvsEpisodes = new CollectionViewSource();
            PropertyChanged(this, new PropertyChangedEventArgs("cvsEpisodes"));
            TimelineArgs args = new TimelineArgs(filter, episodes.ToArray(), offset);
            Frame.Navigate(typeof(Timeline), args);
        }

        private async void MenuFlyoutItem_Click(object sender, RoutedEventArgs e)
        {
            // delete
            var epStart = (DateTime)((MenuFlyoutItem)sender).Tag;
            var find = _episodes.Where(ep =>
            {
                return ep.start == epStart.ToFileTimeUtc();
            });
            if (find.Count() > 0)
            {
                await Memory.Instance.Delete(find.First());
            }
            await RefreshData();
        }

        private void MenuFlyoutItem_Click_1(object sender, RoutedEventArgs e)
        {
            //reveal
            var epStart = (DateTime)((MenuFlyoutItem)sender).Tag;
            var find = episodes.Where(ep =>
            {
                return ep.start.ToFileTimeUtc() == epStart.ToFileTimeUtc();
            });
            if (find.Count() > 0)
            {
                AppInterval ep = find.First();
                string path = Memory.FilePathForEpisode(ep.start.ToFileTimeUtc(), ep.title);
                Debug.WriteLine($"explorer.exe /select, {path}");
                Process.Start("explorer.exe", $"/select, \"{path}\"");
            }
        }

        private async void StartDate_DateChanged(object sender, DatePickerValueChangedEventArgs e)
        {
            start = e.NewDate;
            startDatePicker.Date = start;
            await RefreshData();
        }

        private async void EndDate_DateChanged(object sender, DatePickerValueChangedEventArgs e)
        {
            end = e.NewDate;
            endDatePicker.Date = end;
            await RefreshData();
        }

        private void DeleteAll(object sender, RoutedEventArgs e)
        {
            // Create the message dialog and set its content
            var messageDialog = new MessageDialog("Delete all currently displayed recordings? This action cannot be undone.");
            var hwnd = GetForegroundWindow();
            WinRT.Interop.InitializeWithWindow.Initialize(messageDialog, hwnd);
            messageDialog.Commands.Add(new UICommand(
                "Delete",
                new UICommandInvokedHandler(this.CommandInvokedHandler)));
            messageDialog.Commands.Add(new UICommand(
                "Cancel",
                new UICommandInvokedHandler(this.CommandInvokedHandler)));
            messageDialog.DefaultCommandIndex = 0;
            messageDialog.CancelCommandIndex = 1;
            var ignored = messageDialog.ShowAsync();
        }

        private async void CommandInvokedHandler(IUICommand command)
        {
            Debug.WriteLine(command.Id);
            if( command.Label == "Delete" )
            {
                foreach(var item in _episodes)
                {
                    await Memory.Instance.Delete(item);
                }
                await RefreshData();
            }
        }

        private void searchTextBox_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == VirtualKey.Enter)
            {
                Search(sender, e);
            }
        }

        private async void Button_Click_1(object sender, RoutedEventArgs e)
        {
            showTimelapse = Visibility.Collapsed;
            progressBar.Visibility = Visibility.Visible;
            PropertyChanged(this, new PropertyChangedEventArgs("showTimelapse"));
            PropertyChanged(this, new PropertyChangedEventArgs("progressBar"));
            // Export timelapse
            MediaComposition mediaComposition = new MediaComposition();

            foreach (var episode in _episodes)
            {
                try
                {
                    var _filepath = $"{Memory.PathForEpisode(episode.start)}\\{episode.title}.mov";
                    Debug.WriteLine(_filepath);
                    var _file = await Windows.Storage.StorageFile.GetFileFromPathAsync(_filepath);
                    var videoFile = await MediaClip.CreateFromFileAsync(_file);
                    //videoFile.VideoEffectDefinitions.Add(timelapseEffect);
                    mediaComposition.Clips.Add(videoFile);
                } catch { }
            }

            var filepath = System.IO.Path.Combine(Memory.HomeDirectory(), "Exports");
            Directory.CreateDirectory(filepath);
            var folder = await Windows.Storage.StorageFolder.GetFolderFromPathAsync(filepath);
            var file = await folder.CreateFileAsync($"{DateTime.Now.ToFileTimeUtc()}.mov");
            var profile = mediaComposition.CreateDefaultEncodingProfile();
            profile.Video.Height = 1080;
            profile.Video.Width = 1920;
            var trimming = MediaTrimmingPreference.Precise;
            var renderop = mediaComposition.RenderToFileAsync(file, trimming, profile);
            
            renderop.Progress = new AsyncOperationProgressHandler<TranscodeFailureReason, double>((info, progress) =>
            {
                var _ = DispatcherQueue.TryEnqueue(new Microsoft.UI.Dispatching.DispatcherQueueHandler(() =>
                {
                    Debug.WriteLine(string.Format("Saving file... Progress: {0:F0}%", progress));
                    progressBar.Value = progress;
                    //PropertyChanged(this, new PropertyChangedEventArgs("progressBar"));
                }));
            });
            renderop.Completed = new AsyncOperationWithProgressCompletedHandler<TranscodeFailureReason, double>((info, status) =>
            {
                var _ = DispatcherQueue.TryEnqueue(new Microsoft.UI.Dispatching.DispatcherQueueHandler(() =>
                {
                    try
                    {
                        var results = info.GetResults();
                        if (results != TranscodeFailureReason.None || status != AsyncStatus.Completed)
                        {
                            Debug.WriteLine("Saving was unsuccessful");
                        }
                        else
                        {
                            Debug.WriteLine("Trimmed clip saved to file");
                        }
                    }
                    finally
                    {
                        // Update UI whether the operation succeeded or not
                        Debug.WriteLine(file.Path);
                        Process.Start("explorer.exe", $"/select, \"{file.Path}\"");
                        showTimelapse = Visibility.Visible;
                        progressBar.Visibility = Visibility.Collapsed;
                        PropertyChanged(this, new PropertyChangedEventArgs("showTimelapse"));
                        PropertyChanged(this, new PropertyChangedEventArgs("progressBar"));
                    }

                }));
            });
        }

        private async void BundleChanged(object sender, RoutedEventArgs e)
        {
            string bundle = (string)((Button)sender).Tag;
            if (highlightedBundle.Length > 0)
            {
                highlightedBundle = "";
            }
            else
            {
                highlightedBundle = bundle;
            }
            await RefreshData();
        }
    }
}
