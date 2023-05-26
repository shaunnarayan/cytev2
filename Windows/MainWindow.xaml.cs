// Copyright (c) Microsoft Corporation and Contributors.
// Licensed under the MIT License.

using CyteEncoder;
using Microsoft.UI.Windowing;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using Windows.Foundation;
using WinRT.Interop;
using System.Threading;
using Microsoft.Win32;
using System.Threading.Tasks;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace Cyte
{
    /// <summary>
    /// An empty window that can be used on its own or navigated to within a Frame.
    /// </summary>
    public sealed partial class MainWindow : Window
    {
        AppWindow m_AppWindow;
        public static Size WindowSize { get; private set; } = new Size(0, 0);
        public static MainWindow self { get; private set; }

        public MainWindow()
        {
            Task.Run(async () => await Memory.Instance.Setup()).Wait();
            this.InitializeComponent();
            self = this;

            m_AppWindow = GetAppWindowForCurrentWindow();
            m_AppWindow.Closing += OnClosing;

            // Check to see if customization is supported.
            // Currently only supported on Windows 11.
            if (AppWindowTitleBar.IsCustomizationSupported())
            {
                var titleBar = m_AppWindow.TitleBar;
                titleBar.ExtendsContentIntoTitleBar = true;
                AppTitleBar.Loaded += AppTitleBar_Loaded;
                AppTitleBar.SizeChanged += AppTitleBar_SizeChanged;

                BackButton.Click += OnBackClicked;
                BackButton.Visibility = Visibility.Collapsed;
            }
            else
            {
                // Title bar customization using these APIs is currently
                // supported only on Windows 11. In other cases, hide
                // the custom title bar element.
                //AppTitleBar.Visibility = Visibility.Collapsed;
            }
            
            SystemEvents.PowerModeChanged += OnPowerChange;
        }

        private async void OnPowerChange(object s, PowerModeChangedEventArgs e)
        {
            switch (e.Mode)
            {
                case PowerModes.Resume:
                    Debug.WriteLine("On wake");
                    await Memory.Instance.Setup();
                    break;
                case PowerModes.Suspend:
                    Debug.WriteLine("On sleep");
                    Memory.Instance.Teardown();
                    break;
            }
        }

        public Button BackButton => AppTitleBarBackButton;

        private void OnClosing(object sender, AppWindowClosingEventArgs e)
        {
            Memory.Instance.Teardown();
        }

        private void AppTitleBar_Loaded(object sender, RoutedEventArgs e)
        {
            SetTitleBar(AppTitleBar);
            PageFrame.Navigate(typeof(MainPage));
            if (AppWindowTitleBar.IsCustomizationSupported())
            {
                SetDragRegionForCustomTitleBar(m_AppWindow);
            }
        }

        private void OnBackClicked(object sender, RoutedEventArgs e)
        {
            if (PageFrame.CanGoBack)
            {
                PageFrame.GoBack();
                BackButton.Visibility = Visibility.Collapsed;
            }
        }

        private void AppTitleBar_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            WindowSize = e.NewSize;
            if (AppWindowTitleBar.IsCustomizationSupported()
                && m_AppWindow.TitleBar.ExtendsContentIntoTitleBar)
            {
                // Update drag region if the size of the title bar changes.
                SetDragRegionForCustomTitleBar(m_AppWindow);
            }
        }

        private AppWindow GetAppWindowForCurrentWindow()
        {
            IntPtr hWnd = WindowNative.GetWindowHandle(this);
            WindowId wndId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hWnd);
            return AppWindow.GetFromWindowId(wndId);
        }

        private void SetDragRegionForCustomTitleBar(AppWindow appWindow)
        {
            if (AppWindowTitleBar.IsCustomizationSupported()
                && appWindow.TitleBar.ExtendsContentIntoTitleBar)
            {
                double scaleAdjustment = 1.0;

                RightPaddingColumn.Width = new GridLength(appWindow.TitleBar.RightInset / scaleAdjustment);
                LeftPaddingColumn.Width = new GridLength(appWindow.TitleBar.LeftInset / scaleAdjustment);

                List<Windows.Graphics.RectInt32> dragRectsList = new();

                Windows.Graphics.RectInt32 dragRectL;
                dragRectL.X = (int)((LeftPaddingColumn.ActualWidth + IconColumn.ActualWidth) * scaleAdjustment);
                dragRectL.Y = 0;
                dragRectL.Height = (int)((AppTitleBar.ActualHeight) * scaleAdjustment);
                dragRectL.Width = (int)((TitleColumn.ActualWidth
                                        + DragColumn.ActualWidth) * scaleAdjustment);
                dragRectsList.Add(dragRectL);

                Windows.Graphics.RectInt32[] dragRects = dragRectsList.ToArray();
                appWindow.TitleBar.SetDragRectangles(dragRects);
            }
        }

        private async void Window_Activated(object sender, WindowActivatedEventArgs args)
        {
            Debug.WriteLine("Activated");
            if (MainPage.self != null) {
                Thread.Sleep(1200);
                await MainPage.self.RefreshData();
            }
        }
    }
}
