# Reads the level of Windows' default output device, the same meter the volume
# mixer shows. Lets self-test.ps1 check that sound really reached the speakers
# (or that none did), which a script that merely exits without error cannot say.
# Loaded by self-test.ps1 only; nothing else needs it.

function Initialize-AudioMeter {
    if (-not ('OutputMeter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class OutputMeter
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioMeterInformation {
        int GetPeakValue(out float peak);
    }

    static IAudioMeterInformation meter;

    public static void Open()
    {
        var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0, 1, out device);   // render, multimedia
        var iid = typeof(IAudioMeterInformation).GUID;
        object o;
        device.Activate(ref iid, 23, IntPtr.Zero, out o);
        meter = (IAudioMeterInformation)o;
    }

    public static float Peak()
    {
        float p; meter.GetPeakValue(out p); return p;
    }
}
'@
    }
    [OutputMeter]::Open()
}

# The loudest level (0..1) seen over $Milliseconds.
function Get-AudioPeak {
    param([int]$Milliseconds = 300)
    $peak = 0.0
    $end = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    do {
        $level = [OutputMeter]::Peak()
        if ($level -gt $peak) { $peak = $level }
        Start-Sleep -Milliseconds 20
    } while ([DateTime]::UtcNow -lt $end)
    return $peak
}
