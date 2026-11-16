// android.companion.virtual.VirtualDevice (API 34): one virtual device's public
// details. AOSP: frameworks/base/core/java/android/companion/virtual/VirtualDevice.java.
// Win.apk makes none (VirtualDeviceManager); the type is here for the code that names it.
package android.companion.virtual;

public final class VirtualDevice {
    private final int mId;
    private final String mPersistentId;
    private final String mName;

    /** @hide */
    public VirtualDevice(int id, String persistentId, String name) {
        mId = id;
        mPersistentId = persistentId;
        mName = name;
    }

    public int getDeviceId() { return mId; }
    public String getPersistentDeviceId() { return mPersistentId; }
    public String getName() { return mName; }
    public CharSequence getDisplayName() { return mName; }
    public int[] getDisplayIds() { return new int[0]; }
    public boolean hasCustomSensorSupport() { return false; }
    public boolean hasCustomAudioInputSupport() { return false; }
    public boolean hasCustomCameraSupport() { return false; }
}
