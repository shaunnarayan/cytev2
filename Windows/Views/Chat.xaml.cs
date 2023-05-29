using CyteEncoder;
using System.ComponentModel;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Windows.System;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml;
using System.Collections.Generic;
using System;
using System.Diagnostics;

namespace Cyte
{
    public class ChatArgs
    {
        public string filter { get; }
        public Interval[] intervals { get; }

        public ChatArgs(string _filter, Interval[] _intervals)
        {
            filter = _filter;
            intervals = _intervals;
        }
    }

    public sealed partial class Chat : Page
    {
        public ChatArgs options { get; internal set; }
        public string filter { get; set; } = "";


        public Chat()
        {
            InitializeComponent();
        }

        private void Update(List<ChatItem> log)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                cvsChat.Source = log;
            });
        }

        protected async override void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            options = (ChatArgs)e.Parameter;
            var is_setup = await Agent.Instance.Setup();
            Agent.Instance.Query(this.Update, this.BaseUri, options.filter, options.intervals);
            MainWindow.self.BackButton.Visibility = Visibility.Visible;
        }

        private void Button_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            // Chat
            Agent.Instance.Query(this.Update, this.BaseUri, filterTextBox.Text, options.intervals);
            filterTextBox.Text = "";
        }

        private void TextBox_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == VirtualKey.Enter)
            {
                Debug.WriteLine(filter);
                Agent.Instance.Query(this.Update, this.BaseUri, filterTextBox.Text, options.intervals);
                filterTextBox.Text = "";
            }
        }
    }
}
