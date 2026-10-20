# Guide: Camera on the Xperia 10 V with Sailfish OS

**Important:** This guide is only tested on the Xperia 10 **V** (Zambezi) with Sailfish OS **5.1.0.11** and the Sony binaries **v4b**.

## Preparation

To make the setup easier, download the prepared scripts and files directly to the phone:

~~~sh
devel-su
export REPOTAG="sfos-5.1.0.11-sony-v4b-r1"
export REPOURL="https://github.com/balta3/sailfish-xperia-10v-tweaks/raw/refs/tags/$REPOTAG/camera"
export LOCALDIR="/root/sailfish-xperia-10v-tweaks"
mkdir -p "$LOCALDIR"
curl -fL -o "$LOCALDIR/enable-camera-subsystem.sh" "$REPOURL/scripts/enable-camera-subsystem.sh"
curl -fL -o "$LOCALDIR/prepare-camera-binaries.sh" "$REPOURL/scripts/prepare-camera-binaries.sh"
curl -fL -o "$LOCALDIR/mount-camera-binaries.sh" "$REPOURL/scripts/mount-camera-binaries.sh"
curl -fL -o "$LOCALDIR/sailfish-camera-binaries.service" "$REPOURL/systemd/sailfish-camera-binaries.service"
curl -fL -o "$LOCALDIR/droidmedia-0.20260522.0+1+g6713a08-1.aarch64.rpm" "$REPOURL/rpm/droidmedia-0.20260522.0+1+g6713a08-1.aarch64.rpm"
curl -fL -o "$LOCALDIR/gstreamer1.0-droid-0.20251025.0+camera.xperia10v.video.sf51011.20261019171733.9f338da-1.aarch64.rpm" "$REPOURL/rpm/gstreamer1.0-droid-0.20251025.0+camera.xperia10v.video.sf51011.20261019171733.9f338da-1.aarch64.rpm"
curl -fL -o "$LOCALDIR/SHA256SUMS" "$REPOURL/SHA256SUMS"
cd "$LOCALDIR"
sha256sum -c SHA256SUMS &&
chmod +x enable-camera-subsystem.sh prepare-camera-binaries.sh mount-camera-binaries.sh
~~~

## I: Enable the camera subsystem

Jolla disabled parts of the Android camera subsystem because of the known camera problems in the initial Xperia 10 V port. The normal Android service definitions are still installed, but Sailfish OS overrides them with commands ending in `_HYBRIS_DISABLED`.

Two services have to be re-enabled:

* `mediaextractor`
* `vendor.camera-provider-2-5`

The normal definitions are provided by:

~~~text
/system/etc/init/mediaextractor.rc
/vendor/etc/init/android.hardware.camera.provider@2.5-service_64.rc
~~~

The disabling overrides are provided by:

~~~text
/usr/libexec/droid-hybris/system/etc/init/disabled_services.rc
/usr/libexec/droid-hybris/system/etc/init/disabled_services_device.rc
~~~

### How to fix

The recommended method is to use the provided helper script. It checks the Sailfish OS version, the normal service definitions, and the current contents of both override files. It only changes service blocks that are in a known state.

~~~sh
devel-su
export LOCALDIR="/root/sailfish-xperia-10v-tweaks"
$LOCALDIR/enable-camera-subsystem.sh status
$LOCALDIR/enable-camera-subsystem.sh apply
~~~

The script creates backups of the altered files below `/root/sailfish-xperia-10v-tweaks/backups/`. The manual equivalent is to replace the block in `disabled_services.rc` with exactly:

~~~rc
# sailfish-xperia-10v-tweaks: service mediaextractor /system/bin/mediaextractor_HYBRIS_DISABLED
# sailfish-xperia-10v-tweaks:     override
~~~

and the line in `disabled_services_device.rc` with exactly:

~~~rc
# sailfish-xperia-10v-tweaks: service vendor.camera-provider-2-5 /vendor/bin/hw/android.hardware.camera.provider@2.5-service_64_HYBRIS_DISABLED
~~~

Reboot the phone after applying the change. Then verify both services:

~~~sh
getprop init.svc.mediaextractor
getprop init.svc.vendor.camera-provider-2-5
~~~

Both commands must return `running`.

### Result

* The Jolla Camera app finds all lenses.
* You can use the ultrawide camera for photos. It is still incorrectly labelled `2.0` at this stage.
* You can use the front camera for photos.
* Android apps which allow selecting a camera should be able to use the same working cameras.

## II: Get the main camera working

With the unmodified Sony camera techpack, initialization of the DW9784 optical image stabilization (OIS) controller fails on the Xperia 10 V. This prevents the main camera from initializing. To fix this, we use a patched kernel that incorporates selected initialization routines adapted from the LineageOS kernel for this device.

To use this patched kernel, a boot image based on the kernel version pinned by Jolla is provided. It also includes a small patch for the telephoto camera; see the next step for more information.

The DW9784 changes made against the [Sony camera techpack](https://github.com/sonyxperiadev/kernel-techpack-camera/tree/aosp/LA.UM.9.16.r1) can be found in [this patch](patches/camera-techpack-dw9784.patch).

### How to fix

Before proceeding, make sure you have a copy of the original hybris-boot.img from the corresponding Jolla Sailfish OS installation package. This allows you to restore the original kernel if anything goes wrong.

Power off your Xperia 10 V.

Hold Volume Up while connecting the USB cable to your computer, there should be a blue start on the top left on the screen.

On your computer, run:

~~~sh
export REPOTAG="sfos-5.1.0.11-sony-v4b-r1"
export REPOURL="https://github.com/balta3/sailfish-xperia-10v-tweaks/raw/refs/tags/$REPOTAG/camera"
curl -fL -o hybris-boot-camera.img $REPOURL/images/hybris-boot-camera.img
curl -fL -o SHA256SUMS $REPOURL/images/SHA256SUMS
sha256sum -c SHA256SUMS &&
fastboot flash boot_a hybris-boot-camera.img &&
fastboot flash boot_b hybris-boot-camera.img &&
fastboot reboot
~~~

### Result

* You can now also use the main camera (`1.0` in Jolla Camera) for photos.
* You can use the camera in Android apps that only support the main camera.
* The flashlight will work.

## III: Get the tele camera working

The Sony Zambezi v4b (and later) binaries contain a telephoto camera configuration intended for the Xperia 10 IV (Murray). Although the camera sensor itself can be initialized, the configuration uses parameters for the wrong autofocus actuator.
The Xperia 10 IV uses a GT9772 actuator, whereas the Xperia 10 V uses a GT9769. These actuators require different I²C addresses and initialization sequences. Consequently, the original configuration does not correctly initialize the tele camera on the Xperia 10 V.

The proprietary camera HAL (CamX) reads the actuator configuration from `/odm/lib64/camera/com.sony.sensormodule.murray_tele.bin` and passes the corresponding initialization and focus commands to the kernel camera driver. This file cannot be edited in place and is proprietary to Sony, so I may not redistribute the modified file. In addition, the sensor tuning file from the stock Sony Android binaries should be added for better image quality.

Another problem was that Jolla Camera could not start with the telephoto camera active. It only worked after switching from another camera to the telephoto camera. A [small patch](patches/camera-techpack-gt9769.patch) works around this behaviour.

### How to fix

Two helper scripts are provided to fix the v4b binaries from Sony. You must place one file from the stock Sony Android system in the `/root/sailfish-xperia-10v-tweaks` directory on the phone:

~~~
/odm/lib64/camera/com.qti.tuned.blair_lce_hi847.bin
SHA256: fae940dd8cb3bf567a854cab3dd8cd474ae97b7219b6c9e022cc9d9a7e10b141
~~~

You can then run the prepared script to create the patched camera binary directory:

~~~sh
devel-su
export LOCALDIR="/root/sailfish-xperia-10v-tweaks"
$LOCALDIR/prepare-camera-binaries.sh status
$LOCALDIR/prepare-camera-binaries.sh apply
~~~

After the binaries have been prepared successfully, create a small systemd service that uses a bind mount to override `/odm/lib64/camera` without altering the original files:

~~~sh
devel-su
export LOCALDIR="/root/sailfish-xperia-10v-tweaks"
$LOCALDIR/mount-camera-binaries.sh status
install -m 0644 "$LOCALDIR/sailfish-camera-binaries.service" "/etc/systemd/system/"
systemctl daemon-reload
systemctl enable sailfish-camera-binaries.service
~~~

Reboot the phone to apply the changes.

### Result

* You can now use all available lenses for photos in Jolla Camera and Android apps.

## IV: Video recording fixes

Even after fixing camera initialization and enabling all camera modules, video recording does not work correctly in Jolla Camera because of an additional compatibility issue between the Android 14 camera and media stack used on the Xperia 10 V and the multimedia integration provided by Sailfish OS.

Sailfish OS uses two components to access Android multimedia functionality:

* _droidmedia_ provides access to Android camera services, hardware buffers and media codecs.
* _gst-droid_ integrates these components into the GStreamer framework used by Sailfish OS applications.

The Android camera stack delivers recording frames through a dedicated BufferQueue. The existing GStreamer integration does not correctly handle this recording path on the Xperia 10 V. As a result, recording frames do not reach the video encoder as expected, and starting or stopping video recording may stall.

The following changes were made to get it working:

#### droidmedia

* Mark the recording BufferQueue for hardware video encoder usage.
* Correct the NativeWindowBuffer layer count.
* Preserve codec configuration and sync-frame metadata in encoded output.

#### gst-droid

* Add support for receiving and managing buffers from the dedicated camera recording queue.
* Wrap these buffers in Android VideoNativeMetadata structures for the hardware encoder.
* Ensure buffers are released back to the camera queue after the encoder has finished using them.
* Select the recording queue and metadata path instead of the incompatible legacy external recorder path.
* Work around an Android 14 hardware-only codec discovery issue that prevents the H.264 encoder from being selected.
* Initialize codec callbacks correctly and prevent indefinite waiting for video frames when recording stops.

These changes are made on the latest commit used by Jolla for Sailfish OS 5.1.0.11, so the provided RPMs will not work on any previous or later release. If you're interested you can see the used patch for [droidmedia](patches/droidmedia.patch) and [gst-droid](patches/gst-droid.patch).

### How to fix

~~~sh
devel-su
export LOCALDIR="/root/sailfish-xperia-10v-tweaks"
pkcon install-local "$LOCALDIR"/droidmedia-*.aarch64.rpm "$LOCALDIR"/gstreamer1.0-droid-*.aarch64.rpm
~~~

### Result

* Jolla Camera can record videos with all available lenses.

## V: Fix the camera labels in Jolla Camera

Jolla Camera displays incorrect zoom labels for the rear cameras on the Xperia 10 V. The camera labels are configured through dconf.

### How to fix

~~~sh
# no devel-su! Run this as defaultuser
dconf write /apps/jolla-camera/backCameraLabels "['1.0', '2.1', '0.6']"
~~~

### Result

* The camera labels in Jolla Camera now match the corresponding cameras.
