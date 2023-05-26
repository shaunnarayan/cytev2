using CyteEncoder;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Navigation;
using Windows.Storage;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;
using System.Runtime.InteropServices;
using Microsoft.UI;
using System.Drawing;
using Color = Windows.UI.Color;
using Microsoft.UI.Xaml;
using Windows.UI.Popups;
using System.Diagnostics;

namespace Cyte
{
    public sealed class CyteBundleExclusion
    {
        public string bundle { get; internal set; }
        public string bundleDisplayName { get; internal set; }
        public bool exclude { get; internal set; }
        public BitmapImage thumbnail { get; set; } = new BitmapImage();
        public CyteBundleExclusion(BundleExclusion exclusion)
        {
            bundle = exclusion.bundle;
            exclude = exclusion.exclude;
            try
            {
                var _bundle = new Uri(bundle);
                bundleDisplayName = _bundle.Segments.LastOrDefault().ToString();
            }
            catch { }
        }

        public void Update()
        {
            try
            {
                var filepath = System.IO.Path.Combine(Memory.HomeDirectory(), "Icons", $"{Memory.RemoveInvalid(bundle)}.png");
                thumbnail = new BitmapImage(new Uri(filepath));
            }
            catch { }
        }
    }
    public sealed partial class Settings : Page, INotifyPropertyChanged
    {
        [DllImport("user32.dll")]
        static extern IntPtr GetForegroundWindow();

        public event PropertyChangedEventHandler PropertyChanged;
        public BundleExclusion[] bundleExclusions { get; set; }
        public string homeDirectory { get; set; } = Memory.HomeDirectory();
        public string apiKey { get; set; } = "";
        public Settings()
        {
            this.InitializeComponent();
            var localSettings = ApplicationData.Current.LocalSettings;
            
            var retain = localSettings.Values["CYTE_RETENTION"];
            if( retain != null)
            {
                var bg = Color.FromArgb(0xff, 0xA0, 0xA0, 0xff);
                switch ( retain )
                {
                    case 0:
                        retain0.Background = new SolidColorBrush(bg);
                        break;
                    case 30:
                        retain1.Background = new SolidColorBrush(bg);
                        break;
                    case 60:
                        retain2.Background = new SolidColorBrush(bg);
                        break;
                    case 90:
                        retain3.Background = new SolidColorBrush(bg);
                        break;
                    default:
                        break;
                }
            }
            var home = localSettings.Values["CYTE_HOME"];
            if( home != null )
            {
                homeDirectory = (string)home;
            }

            // Check if the vault contains a key
            var vault = new Windows.Security.Credentials.PasswordVault();
            var passwords = vault.RetrieveAll();
            if(passwords.Count > 0)
            {
                apiKeyTextBox.Text = "";
                apiKeyTextBox.PlaceholderText = "Knowledge base enabled";
                apiKeyTextBox.IsEnabled = false;
                apiKeyTextBox.Background = new SolidColorBrush(Color.FromArgb(0xff, 0xA0, 0xA0, 0xff));
                saveApiButton.Source = new BitmapImage(new Uri(this.BaseUri, "/Assets/x.png"));
            }
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            // update state from prefs
            ReloadBundles();
            MainWindow.self.BackButton.Visibility = Visibility.Visible;
            base.OnNavigatedTo(e);
        }

        private void ReloadBundles()
        {
            bundleExclusions = BundleExclusion.GetList();
            var exclusions = new List<CyteBundleExclusion>();
            foreach (var exclusion in bundleExclusions)
            {
                var ex = new CyteBundleExclusion(exclusion);
                ex.Update();
                exclusions.Add(ex);
            }
            cvsBundles.Source = exclusions;
        }

        private async void CheckBox_Checked(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            var bundle = (string) ((CheckBox)sender).Tag;
            var find = bundleExclusions.Where(ep =>
            {
                return ep.bundle == bundle;
            });
            if (find.Count() > 0)
            {
                var ex = find.First();
                ex.exclude = !ex.exclude;
                if (ex.exclude)
                {
                    var eps = Episode.GetList($" WHERE bundle == '{ex.bundle}'", "");
                    foreach (var item in eps)
                    {
                        await Memory.Instance.Delete(item);
                    }
                }
                ex.Save();
            }
        }

        private void CommandInvokedHandler(IUICommand command)
        {
            //
        }

        private async void Button_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            // save the API key to vault and setup agent
            var vault = new Windows.Security.Credentials.PasswordVault();
            var passwords = vault.RetrieveAll();
            if (passwords.Count > 0)
            {
                foreach (var item in passwords)
                {
                    vault.Remove(item);
                }
                apiKeyTextBox.Text = "";
                apiKeyTextBox.PlaceholderText = "API Key or llama.cpp model path";
                apiKeyTextBox.IsEnabled = true;
                apiKeyTextBox.Background = new SolidColorBrush(Colors.White);
                saveApiButton.Source = new BitmapImage(new Uri(this.BaseUri, "/Assets/cloud-check.png"));
                PropertyChanged(this, new PropertyChangedEventArgs("saveApiButton"));
                PropertyChanged(this, new PropertyChangedEventArgs("apiKeyTextBox"));
                Agent.Instance.Teardown();
            }
            else
            {
                apiKeyTextBox.IsEnabled = false;
                saveApiButton.IsTapEnabled = false;
                var key = new Windows.Security.Credentials.PasswordCredential("Cyte", "OpenAI", apiKey);
                vault.Add(key);
                bool is_setup = await Agent.Instance.Setup();
                if (!is_setup)
                {
                    var messageDialog = new MessageDialog("Language model could not be loaded - is the API key or path valid, and is it a supported model?");
                    var hwnd = GetForegroundWindow();
                    WinRT.Interop.InitializeWithWindow.Initialize(messageDialog, hwnd);
                    messageDialog.Commands.Add(new UICommand(
                        "OK",
                        new UICommandInvokedHandler(this.CommandInvokedHandler)));
                    messageDialog.DefaultCommandIndex = 0;
                    messageDialog.CancelCommandIndex = 0;
                    var ignored = messageDialog.ShowAsync();
                    apiKeyTextBox.IsEnabled = true;
                    saveApiButton.IsTapEnabled = true;
                    return;
                }
                apiKey = "";
                apiKeyTextBox.Text = "";
                apiKeyTextBox.PlaceholderText = "Knowledge base enabled";
                apiKeyTextBox.IsEnabled = false;
                apiKeyTextBox.Background = new SolidColorBrush(Color.FromArgb(0xff, 0xA0, 0xA0, 0xff));
                saveApiButton.Source = new BitmapImage(new Uri(this.BaseUri, "/Assets/x.png"));
                PropertyChanged(this, new PropertyChangedEventArgs("saveApiButton"));
                PropertyChanged(this, new PropertyChangedEventArgs("apiKeyTextBox"));
            }
        }
        
        private void ChangeRetention(int index)
        {
            var localSettings = ApplicationData.Current.LocalSettings;
            localSettings.Values["CYTE_RETENTION"] = index * 30;
            var bg = Color.FromArgb(0xff, 0xA0, 0xA0, 0xff);
            var _def = SystemColors.Control;
            var def = Color.FromArgb(_def.A, _def.R, _def.G, _def.B);
            retain0.Background = new SolidColorBrush(index == 0 ? bg : def);
            retain1.Background = new SolidColorBrush(index == 1 ? bg : def);
            retain2.Background = new SolidColorBrush(index == 2 ? bg : def);
            retain3.Background = new SolidColorBrush(index == 3 ? bg : def);
        }

        private void retain0_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            ChangeRetention(0);
        }

        private void retain1_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            ChangeRetention(1);
        }

        private void retain2_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            ChangeRetention(2);
        }

        private void retain3_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            ChangeRetention(3);
        }

        private async void Button_Click_1(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            FolderPicker folderPicker = new();
            folderPicker.FileTypeFilter.Add("*");

            var hwnd = GetForegroundWindow();
            WinRT.Interop.InitializeWithWindow.Initialize(folderPicker, hwnd);

            StorageFolder folder = await folderPicker.PickSingleFolderAsync();
            if (folder != null)
            {
                var localSettings = ApplicationData.Current.LocalSettings;
                localSettings.Values["CYTE_HOME"] = folder.Path;
                homeDirectory = folder.Path;
                PropertyChanged(this, new PropertyChangedEventArgs("homeDirectory"));

                Memory.Instance.Reload();
                ReloadBundles();
            }
        }
    }
}
