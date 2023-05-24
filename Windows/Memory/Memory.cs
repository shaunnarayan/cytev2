using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Data.Sqlite;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Storage;
using DiffMatchPatch;
using Windows.Graphics.Capture;
using System.IO;
using Windows.Media.Ocr;
using Windows.Graphics.Imaging;
using System.Collections.Generic;
using System.Threading;
using Windows.Storage.Streams;
using System.Threading.Tasks;
using Windows.Graphics.Display;
using Windows.Security.Authorization.AppCapabilityAccess;
using Windows.System;
using System.Linq;

namespace CyteEncoder
{
    public sealed class Episode
    {
        public long id { get; internal set; }
        public string title { get; internal set; }
        public long start { get; internal set; }
        public long end { get; internal set; }
        public string bundle { get; internal set; }
        public bool save { get; set; }

        public void Insert()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"INSERT INTO Episode (""title"", ""start"", ""end"", ""bundle"", ""save"") VALUES($title, $start, $end, $bundle, $save)";
                command.Parameters.AddWithValue("$title", title);
                command.Parameters.AddWithValue("$start", start);
                command.Parameters.AddWithValue("$end", end);
                command.Parameters.AddWithValue("$bundle", bundle);
                command.Parameters.AddWithValue("$save", save);
                command.ExecuteNonQuery();
            }
        }

        public static Episode[] GetList(string predicate, string limit)
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    $"SELECT * FROM Episode{predicate} ORDER BY start DESC{limit}";
                var episodes = new List<Episode>();
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var title = reader.GetString(1);
                        var start = reader.GetInt64(2);
                        var end = reader.GetInt64(3);
                        var bundle = reader.GetString(4);
                        var save = reader.GetBoolean(5);
                        var episode = new Episode(title, start, end, save, bundle);
                        episode.id = reader.GetInt32(0);
                        episodes.Add(episode);
                    }
                }
                return episodes.ToArray();
            }
        }

        public static Episode Fetch(long when)
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    $"SELECT * FROM Episode WHERE start == $start";
                command.Parameters.AddWithValue("$start", when);
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var title = reader.GetString(1);
                        var start = reader.GetInt64(2);
                        var end = reader.GetInt64(3);
                        var bundle = reader.GetString(4);
                        var save = reader.GetBoolean(5);
                        var episode = new Episode(title, start, end, save, bundle);
                        episode.id = reader.GetInt32(0);
                        return episode;
                    }
                }
            }
            return null;
        }

        public void Delete()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"DELETE FROM Episode WHERE id = $eid";
                command.Parameters.AddWithValue("$eid", id);
                command.ExecuteNonQuery();
            }
        }

        public void Save()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"UPDATE Episode SET title = $title, start = $start, end = $end, bundle = $bundle, save = $save WHERE id = $bid";
                command.Parameters.AddWithValue("$title", title);
                command.Parameters.AddWithValue("$start", start);
                command.Parameters.AddWithValue("$end", end);
                command.Parameters.AddWithValue("$bundle", bundle);
                command.Parameters.AddWithValue("$save", save);
                command.Parameters.AddWithValue("$bid", id);
                command.ExecuteNonQuery();
            }
        }

        public Episode(string _title, long _start, long _end, bool _save, string _bundle)
        {
            title = _title;
            start = _start;
            end = _end;
            bundle = _bundle;
            save = _save;
        }

        public Episode()
        {

        }
    }

    public sealed class Interval
    {
        public Episode episode { get; internal set; }
        public long from { get; internal set; }
        public long to { get; internal set; }
        public string document { get; internal set; }

        public static Interval[] GetList(Episode episode)
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    $"SELECT * FROM Interval WHERE episode_start = $start";
                command.Parameters.AddWithValue("$start", episode.start);
                var intervals = new List<Interval>();
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var from = reader.GetInt64(0);
                        var to = reader.GetInt64(1);
                        var episode_start = reader.GetInt64(2);
                        var document = reader.GetString(3);
                        var interval = new Interval(from, to, episode, document);
                        intervals.Add(interval);
                    }
                }
                return intervals.ToArray();
            }
        }

        public void Insert()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"INSERT INTO Interval(""from"", ""to"", ""episode_start"", ""document"") VALUES($from, $to, $episode_start, $document)";
                command.Parameters.AddWithValue("$from", from);
                command.Parameters.AddWithValue("$to", to);
                command.Parameters.AddWithValue("$episode_start", episode.start);
                command.Parameters.AddWithValue("$document", document);
                command.ExecuteNonQuery();
            }
        }

        public void Delete()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"DELETE FROM Interval WHERE episode_start = $start";
                command.Parameters.AddWithValue("$start", episode.start);
                command.ExecuteNonQuery();
            }
        }

        public Interval(long _from, long _to, Episode _episode, string _document)
        {
            from = _from;
            to = _to;
            episode = _episode;
            document = _document;
        }

    }

    public sealed class BundleExclusion
    {
        public long id { get; internal set; }
        public string bundle { get; internal set; }
        public bool exclude { get; set; }

        public static BundleExclusion Fetch(string bundle)
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    $"SELECT * FROM BundleExclusion WHERE bundle == $bundle";
                command.Parameters.AddWithValue("$bundle", bundle);
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var _bundle = reader.GetString(1);
                        var _exclude = reader.GetBoolean(2);
                        var item = new BundleExclusion(_bundle, _exclude);
                        item.id = reader.GetInt32(0);
                        return item;
                    }
                }
            }
            return null;
        }

        public void Insert()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"INSERT INTO BundleExclusion (""bundle"", ""exclude"") VALUES($bundle, $exclude)";
                command.Parameters.AddWithValue("$bundle", bundle);
                command.Parameters.AddWithValue("$exclude", exclude);
                command.ExecuteNonQuery();
            }
        }

        public static BundleExclusion[] GetList()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    $"SELECT * FROM BundleExclusion";
                var bundles = new List<BundleExclusion>();
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var bundle = reader.GetString(1);
                        var exclude = reader.GetBoolean(2);
                        var item = new BundleExclusion(bundle, exclude);
                        item.id = reader.GetInt32(0);
                        bundles.Add(item);
                    }
                }
                return bundles.ToArray();
            }
        }

        public void Save()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"UPDATE BundleExclusion SET bundle = $bundle, exclude = $exclude WHERE id = $bid";
                command.Parameters.AddWithValue("$bundle", bundle);
                command.Parameters.AddWithValue("$exclude", exclude);
                command.Parameters.AddWithValue("$bid", id);
                command.ExecuteNonQuery();
            }
        }

        public void Delete()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"DELETE FROM BundleExclusion WHERE id = $bid";
                command.Parameters.AddWithValue("$bid", id);
                command.ExecuteNonQuery();
            }
        }

        public BundleExclusion(string _bundle, bool _exclude)
        {
            bundle = _bundle;
            exclude = _exclude;
        }

    }

    public class Memory
    {
        private static readonly Lazy<Memory> lazy = new Lazy<Memory>(() => new Memory());

        [DllImport("user32.dll")]
        static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        private GraphicsCaptureItem _item;
        private Encoder _encoder = null;
        private Thread timer;
        private bool isRunning = false;

        private int frameCount = 0;
        private DateTime currentStart = DateTime.Now;
        private Episode episode = new Episode();
        private string lastObservation = "";

        private string currentContext = "Startup";
        private OcrEngine engine = OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en"));
        private bool isProcessing = false;
        private bool isEncoding = false;
        private uint dropouts = 0;

        public static Memory Instance
        {
            get { return lazy.Value; }
        }

        public static string HomeDirectory()
        {
            var folder = Environment.SpecialFolder.MyDocuments;
            var home = System.IO.Path.Combine(Environment.GetFolderPath(folder), "Cyte");
            var localSettings = ApplicationData.Current.LocalSettings;

            var user_home = localSettings.Values["CYTE_HOME"];
            if (user_home != null)
            {
                home = (string)user_home;
            }
            return home;
        }

        public static string DatabasePath()
        {
            return System.IO.Path.Combine(Memory.HomeDirectory(), "Cyte.sqlite");
        }

        public static string FilePathForEpisode(long offset, string title)
        {
            var time = DateTime.FromFileTimeUtc(offset);
            return System.IO.Path.Combine(Memory.HomeDirectory(), time.Year.ToString(), time.Month.ToString(), time.Day.ToString(), $"{title}.mov");
        }

        public static string PathForEpisode(long offset)
        {
            var time = DateTime.FromFileTimeUtc(offset);
            return System.IO.Path.Combine(Memory.HomeDirectory(), time.Year.ToString(), time.Month.ToString(), time.Day.ToString());
        }

        private Memory()
        {
            Debug.WriteLine("Init memory");
        }

        public async static void TimerProc()
        {
            long update_ms = 1000;
            while (Memory.Instance.isRunning)
            {
                var start = DateTime.Now;
                await Memory.Instance.UpdateActiveContext();
                var end = DateTime.Now;
                var elapased = end - start;
                Thread.Sleep((int)Math.Max(0, update_ms - elapased.TotalMilliseconds));
            }
        }

        public async void Setup()
        {
            var accessResult = await GraphicsCaptureAccess.RequestAccessAsync(GraphicsCaptureAccessKind.Programmatic);
            if (accessResult == AppCapabilityAccessStatus.Allowed)
            {
                var ignoredResult = await GraphicsCaptureAccess.RequestAccessAsync(GraphicsCaptureAccessKind.Borderless);
                DiagnosticAccessStatus diagnosticAccessStatus = await AppDiagnosticInfo.RequestAccessAsync();

                var displays = DisplayServices.FindAll();
                var item = GraphicsCaptureItem.TryCreateFromDisplayId(displays.First());

                var dir = Directory.CreateDirectory(Memory.HomeDirectory());
                Debug.WriteLine(dir.CreationTime);
                migrate();

                _item = item;
                isRunning = true;
                timer = new Thread(new ThreadStart(TimerProc));
                timer.Start();
            }
            else
            {
                //@todo handle error
            }
        }

        public void Teardown()
        {
            isRunning = false;
            CloseEpisode();
            timer.Join();
        }

        public static string RemoveInvalid(string path)
        {
            foreach (char c in System.IO.Path.GetInvalidFileNameChars())
            {
                path = path.Replace(c, '_');
            }
            return path;
        }

        async Task<bool> UpdateActiveContext()
        {
            IntPtr hWnd = GetForegroundWindow();
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            Process proc = null;
            var newContext = "";
            try
            {
                proc = System.Diagnostics.Process.GetProcessById((int)processId);
                newContext = proc.MainModule.FileName.ToLower();
                var iconPath = proc.MainModule.FileName;

                var filepath = System.IO.Path.Combine(Memory.HomeDirectory(), "Icons");
                var dir = Directory.CreateDirectory(filepath);
                var folder = await Windows.Storage.StorageFolder.GetFolderFromPathAsync(filepath);
                var exists = await folder.TryGetItemAsync($"{Memory.RemoveInvalid(newContext)}.png");
                if (exists == null)
                {
                    try
                    {
                        var destinationFile = await folder.CreateFileAsync($"{Memory.RemoveInvalid(newContext)}.png");

                        // Load the file into a StorageFile object
                        var appFile = await Windows.Storage.StorageFile.GetFileFromPathAsync(iconPath);
                        // Get the app thumbnail
                        var appThumbnail = await appFile.GetThumbnailAsync(Windows.Storage.FileProperties.ThumbnailMode.SingleItem);

                        Windows.Storage.Streams.Buffer MyBuffer = new Windows.Storage.Streams.Buffer(Convert.ToUInt32(appThumbnail.Size));
                        IBuffer iBuf = await appThumbnail.ReadAsync(MyBuffer, MyBuffer.Capacity, InputStreamOptions.None);
                        using (var strm = await destinationFile.OpenAsync(FileAccessMode.ReadWrite))
                        {
                            await strm.WriteAsync(iBuf);
                        }
                    }
                    catch { }
                }
            }
            catch { } //Most likely failed to access the process

            if (currentContext != newContext)
            {
                Debug.WriteLine("Closing episode");
                CloseEpisode();
                Debug.WriteLine("Closed episode");
                currentContext = newContext;
                if (proc != null && currentContext != "" && proc.Id != Process.GetCurrentProcess().Id)
                {
                    TryCreateBundle(currentContext);
                    BundleExclusion exclusion = BundleExclusion.Fetch(newContext);
                    if (exclusion.exclude == false)
                    {
                        OpenEpisode(proc.MainWindowTitle);
                    }
                    else
                    {
                        Debug.WriteLine($"Bypass private context {newContext}");
                    }
                }
            }
            return true;
        }

        private async Task<bool> OpenEpisode(string title)
        {
            Debug.WriteLine($"Opening {title}");
            // Encoders generally like even numbers
            var width = (uint)_item.Size.Width;
            var height = (uint)_item.Size.Height;

            // Find a place to put our vidoe for now
            currentStart = DateTime.Now;
            foreach (char c in System.IO.Path.GetInvalidFileNameChars())
            {
                title = title.Replace(c, '_');
            }
            title = $"{title.Substring(0, Math.Min(title.Length, 200))} {currentStart.ToFileTimeUtc()}";

            var filepath = Memory.PathForEpisode(currentStart.ToFileTimeUtc());
            Directory.CreateDirectory(filepath);

            episode.title = title;
            episode.start = currentStart.ToFileTimeUtc();
            episode.end = currentStart.ToFileTimeUtc();
            episode.bundle = currentContext;
            episode.save = false;

            // Kick off the encoding
            isEncoding = true;
            var folder = await Windows.Storage.StorageFolder.GetFolderFromPathAsync(filepath);
            var file = await folder.CreateFileAsync($"{title}.mov");
            try
            {
                using (var stream = await file.OpenAsync(FileAccessMode.ReadWrite))
                using (_encoder = new Encoder(_item))
                {
                    Debug.WriteLine("StartEnc");
                    await _encoder.EncodeAsync(
                        stream,
                        width, height, 1600000,
                        0.5);
                    Debug.WriteLine("StopEnc");
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.Message);
                Debug.WriteLine(ex);
            }
            Debug.WriteLine("Switching context");
            // save episode into db
            episode.end = DateTime.Now.ToFileTimeUtc();
            episode.Insert();
            if (frameCount <= 0)
            {
                await Delete(episode);
            }
            isEncoding = false;
            return true;
        }

        public void CloseEpisode()
        {
            if (_encoder == null) { return; }
            _encoder?.Dispose();
            _encoder = null;
            while (isEncoding == true)
            {
                Debug.WriteLine("Waiting for encoder to finish...");
                Thread.Sleep(100);
            }
            frameCount = 0;
            RunRetention();
        }

        private void RunRetention()
        {
            var localSettings = ApplicationData.Current.LocalSettings;
            int retain = (int)localSettings.Values["CYTE_RETENTION"];
            if (retain == 0)
            {
                return;
            }
            var cutoff = DateTime.Now.AddDays(-retain);
            Debug.WriteLine($"Culling memories before: {cutoff.ToString()}");
            Episode[] cull = Episode.GetList($" WHERE start < {cutoff.ToFileTimeUtc()}", "");
            foreach (var c in cull)
            {
                Delete(c);
            }
        }

        public async Task<bool> OnFrame(IDirect3DSurface sample)
        {
            if (engine == null || sample == null || isProcessing)
            {
                dropouts++;
                Debug.WriteLine($"Frame dropout, total {dropouts}");
                return false;
            }
            isProcessing = true;
            var start = DateTime.Now;

            try
            {
                var softwareBitmap = await SoftwareBitmap.CreateCopyFromSurfaceAsync(sample, BitmapAlphaMode.Straight);
                var ocrResults = await engine.RecognizeAsync(softwareBitmap);
                var text2 = ocrResults.Text;
                Console.Write(text2);
                var diffs = DiffMatchPatchModule.Default.DiffMain(lastObservation, text2);
                DiffMatchPatchModule.Default.DiffCleanupSemantic(diffs);

                var added = "";
                foreach (var diff in diffs)
                {
                    if (diff.Operation == Operation.Insert)
                    {
                        added += diff.Text;
                    }
                }

                var interval = new Interval(start.ToFileTimeUtc(), start.AddSeconds(2).ToFileTimeUtc(), episode, added);
                interval.Insert();
                lastObservation = added;
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
            }
            frameCount++;
            isProcessing = false;
            return true;
        }

        private string expand(string term, int by)
        {
            // @todo use POS tags and embeddings to expand the query
            return term;
        }

        public Interval[] Search(string term)
        {
            int expand_by = 0;
            List<Interval> results = new List<Interval>();
            var finalTerm = expand(term, expand_by);

            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText = finalTerm.Length > 0 ?
                    $"SELECT *, snippet(Interval, -1, '', '', '', 1) FROM Interval WHERE Interval MATCH $what ORDER BY bm25(Interval) LIMIT 32" :
                    $"SELECT *, snippet(Interval, -1, '', '', '', 1) FROM Interval LIMIT 32";
                command.Parameters.AddWithValue("$what", finalTerm);
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var from = reader.GetInt64(0);
                        var to = reader.GetInt64(1);
                        var episode_start = reader.GetInt64(2);
                        var episode = Episode.Fetch(episode_start);
                        var document = reader.GetString(3);
                        var interval = new Interval(from, to, episode, document);
                        results.Add(interval);
                    }
                }
            }

            return results.ToArray();
        }

        public async Task<bool> Delete(Episode episode)
        {
            // get intervals and delete
            foreach (var interval in Interval.GetList(episode))
            {
                interval.Delete();
            }
            try
            {
                var filepath = System.IO.Path.Combine(Memory.PathForEpisode(episode.start), $"{episode.title}.mov");
                var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(filepath);
                await file.DeleteAsync();
            }
            catch { }
            episode.Delete();
            return true;
        }

        private void TryCreateBundle(string name)
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                try
                {
                    connection.Open();
                    var command = connection.CreateCommand();
                    command.CommandText =
                        @"INSERT INTO BundleExclusion (""bundle"", ""exclude"") VALUES($bundle, $exclude)";
                    command.Parameters.AddWithValue("$bundle", name);
                    command.Parameters.AddWithValue("$exclude", false);
                    command.ExecuteNonQuery();
                }
                catch { }// is fine
            }
        }

        public void Reload()
        {
            migrate();
        }

        private void migrate()
        {
            using (var connection = new SqliteConnection($"Data Source={Memory.DatabasePath()}"))
            {
                connection.Open();
                var command = connection.CreateCommand();
                command.CommandText =
                    @"CREATE TABLE IF NOT EXISTS ""Episode"" (
	                ""id""	INTEGER,
	                ""title""	TEXT NOT NULL,
	                ""start""	INTEGER NOT NULL UNIQUE,
	                ""end""	INTEGER NOT NULL UNIQUE,
	                ""bundle""	TEXT NOT NULL,
	                ""save""	INTEGER NOT NULL DEFAULT 0,
	                PRIMARY KEY(""id"" AUTOINCREMENT)
                )";
                command.ExecuteNonQuery();

                command = connection.CreateCommand();
                command.CommandText =
                    @"CREATE VIRTUAL TABLE IF NOT EXISTS ""Interval"" USING fts5(
	                ""from"",
	                ""to"",
	                ""episode_start"",
	                ""document""
                )";
                command.ExecuteNonQuery();

                command = connection.CreateCommand();
                command.CommandText =
                    @"CREATE TABLE IF NOT EXISTS ""BundleExclusion"" (
                    ""id""	INTEGER,
	                ""bundle""	TEXT NOT NULL UNIQUE,
	                ""exclude""	INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(""id"" AUTOINCREMENT)
                )";
                command.ExecuteNonQuery();
            }
        }
    }
}
