using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
class Launcher {
    [STAThread] static void Main(string[] args) {
        string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launcher.ps1");
        string options = "";
        foreach (string arg in args) {
            if (arg == "--stop") options += " -Stop";
            if (arg == "--no-browser") options += " -NoBrowser";
            if (arg == "--headless") options += " -Headless";
        }
        try {
            var info = new ProcessStartInfo("powershell.exe", "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"" + options);
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            var process = Process.Start(info);
            if (Array.IndexOf(args, "--stop") >= 0) process.WaitForExit();
        } catch (Exception error) {
            MessageBox.Show(error.Message, "Электронная очередь", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
