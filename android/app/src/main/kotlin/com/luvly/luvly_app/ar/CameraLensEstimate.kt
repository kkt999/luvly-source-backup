package com.luvly.luvly_app.ar

import android.hardware.camera2.CameraCharacteristics
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.CameraInfo

/** Read-only lens metadata; no calibration, permission change or camera upload. */
object CameraLensEstimate {
    @androidx.annotation.OptIn(markerClass=[ExperimentalCamera2Interop::class])
    fun read(info: CameraInfo): SensorLens? = runCatching {
        val camera=Camera2CameraInfo.from(info)
        val sensor=camera.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            ?: return@runCatching null
        val focal=camera.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            ?.firstOrNull() ?: return@runCatching null
        SensorLens(sensor.width,sensor.height,focal)
    }.getOrNull()
}
