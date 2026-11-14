// android.companion.virtual.VirtualDeviceManager (API 34): the virtual devices a
// companion app has made on this device (a car's screen, a streamed desktop).
// AOSP: frameworks/base/core/java/android/companion/virtual/VirtualDeviceManager.java.
//
// Win.apk: there are none, which is what a phone with no such companion
// answers: an empty list, and no device for any id but the default one. The
// class was missing; apps reach it behind `SDK_INT >= 34` (Google Translate on
// its main thread at start, five more of the popular apps), where it was a
// NoClassDefFoundError.
package android.companion.virtual;

import android.content.Context;

import java.util.Collections;
import java.util.List;

public final class VirtualDeviceManager {
    /** @hide: made by Context.getSystemService(Context.VIRTUAL_DEVICE_SERVICE). */
    public VirtualDeviceManager(Context context) {}

    public List<VirtualDevice> getVirtualDevices() { return Collections.emptyList(); }

    /** The device with this id, or null: only virtual devices have one, and there are none. */
    public VirtualDevice getVirtualDevice(int deviceId) { return null; }
}
