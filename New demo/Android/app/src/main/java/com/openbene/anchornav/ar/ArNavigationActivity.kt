package com.openbene.anchornav.ar

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.material.materialswitch.MaterialSwitch
import com.google.ar.core.ArCoreApk
import com.google.ar.core.AugmentedImage
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.openbene.anchornav.DemoState
import com.openbene.anchornav.R
import com.openbene.anchornav.nav.ArObservation
import com.openbene.anchornav.nav.ExecutorState
import com.openbene.anchornav.nav.ExecutorStatus
import com.openbene.anchornav.nav.FollowCommand
import com.openbene.anchornav.nav.FollowConfig
import com.openbene.anchornav.nav.FollowController
import com.openbene.anchornav.nav.GuidanceBuilder
import com.openbene.anchornav.nav.GuidanceStep
import com.openbene.anchornav.nav.MapData
import com.openbene.anchornav.nav.PoseEstimator
import com.openbene.anchornav.nav.Pose2D
import com.openbene.anchornav.nav.RobotLink
import com.openbene.anchornav.nav.Route
import com.openbene.anchornav.nav.RouteExecutor
import com.openbene.anchornav.nav.Router
import com.openbene.anchornav.robot.PersonBoxDetector
import java.util.Locale
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * The AR half of the Android demo: the phone rides on the OpenBot, ARCore keeps
 * the pose, the printed sheets re-localise it and the route executor drives the
 * robot to the selected room.
 *
 * Marker fixes come from two sources, in order of accuracy:
 *
 * 1. ARCore augmented image tracking, using a database built at run time from
 *    the same PNG sheets that are printed and taped to the floor;
 * 2. the QR payload of the same sheet, decoded with ML Kit, where the corner
 *    pixels are turned into a floor quad by [MarkerGeometry].
 *
 * Both end up as one [ArObservation], so the executor does not care which one
 * produced the fix.
 */
class ArNavigationActivity : AppCompatActivity(), GLSurfaceView.Renderer {

    private lateinit var surfaceView: GLSurfaceView
    private lateinit var overlayView: RouteOverlayView
    private lateinit var stateText: TextView
    private lateinit var detailText: TextView
    private lateinit var guidanceText: TextView
    private lateinit var startDrivingButton: Button
    private lateinit var modeSwitch: MaterialSwitch

    private lateinit var displayRotationHelper: DisplayRotationHelper
    private val backgroundRenderer = CameraBackgroundRenderer()
    private val qrScanner = QrScanner()
    private val followDetector = PersonBoxDetector()
    private val followConfig = FollowConfig.FACE_BOX

    private var session: Session? = null
    private var installRequested = false

    private var mapData: MapData? = null
    private var route: Route? = null
    private var guidanceSteps: List<GuidanceStep> = emptyList()
    private var estimator: PoseEstimator? = null
    private var executor: RouteExecutor? = null
    private var link: RobotLink? = null

    private var drivingArmed = false
    private var followMode = false
    private var lastFollowCommand: FollowCommand? = null
    private var lastFrameTimeS = 0.0
    private var lastCameraRequestS = -10.0
    private var lastUiUpdateS = -10.0
    private var knownFloorY: Double? = null
    private var lastStatus: ExecutorStatus? = null
    private var sessionIntrinsics: CameraIntrinsics? = null
    private var sessionIntrinsicsSize: Pair<Int, Int>? = null
    private var sensorOrientationDegrees = SENSOR_ORIENTATION_DEFAULT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ar_navigation)

        surfaceView = findViewById(R.id.surfaceView)
        overlayView = findViewById(R.id.routeOverlayView)
        stateText = findViewById(R.id.stateText)
        detailText = findViewById(R.id.detailText)
        guidanceText = findViewById(R.id.guidanceText)
        startDrivingButton = findViewById(R.id.startDrivingButton)
        modeSwitch = findViewById(R.id.modeSwitch)
        val stopButton: Button = findViewById(R.id.stopButton)

        displayRotationHelper = DisplayRotationHelper(this)

        val map = try {
            DemoState.map(this)
        } catch (error: Exception) {
            Toast.makeText(this, getString(R.string.map_load_failed, error.message ?: ""), Toast.LENGTH_LONG).show()
            finish()
            return
        }
        mapData = map
        overlayView.bind(map)

        val built = Router(map).routeToRoom(DemoState.START_LOCATION_ID, DemoState.selectedRoomName)
        if (built == null) {
            Toast.makeText(this, getString(R.string.map_load_failed, DemoState.selectedRoomName), Toast.LENGTH_LONG).show()
            finish()
            return
        }
        route = built
        guidanceSteps = GuidanceBuilder(map).build(built)
        overlayView.setRoute(built)
        guidanceText.text = guidanceSteps.firstOrNull()?.message ?: ""

        val pose = PoseEstimator(map)
        estimator = pose
        val robotLink = DemoState.createLink(this)
        link = robotLink
        executor = RouteExecutor(map, pose, robotLink)

        startDrivingButton.isEnabled = false
        startDrivingButton.setOnClickListener {
            if (followMode) {
                drivingArmed = true
                startDrivingButton.isEnabled = false
                guidanceText.text = getString(R.string.follow_armed)
                return@setOnClickListener
            }
            val active = executor ?: return@setOnClickListener
            if (!(estimator?.aligned ?: false)) return@setOnClickListener
            active.start(built, DemoState.START_LOCATION_ID)
            drivingArmed = true
            startDrivingButton.isEnabled = false
        }
        stopButton.setOnClickListener {
            stopEverything()
            finish()
        }
        modeSwitch.setOnCheckedChangeListener { _, checked ->
            followMode = checked
            drivingArmed = false
            executor?.stop()
            robotLink.stop()
            lastFollowCommand = null
            lastStatus = null
            startDrivingButton.isEnabled = followMode || (estimator?.aligned ?: false)
            guidanceText.text = if (followMode) {
                getString(R.string.follow_ready)
            } else {
                guidanceSteps.firstOrNull()?.message ?: ""
            }
        }

        surfaceView.preserveEGLContextOnPause = true
        surfaceView.setEGLContextClientVersion(2)
        surfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        surfaceView.setRenderer(this)
        surfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

        if (!hasCameraPermission()) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA)
        }
    }

    override fun onResume() {
        super.onResume()
        displayRotationHelper.onResume()
        if (session == null && hasCameraPermission() && ensureArCore()) {
            createSession()
        }
        session?.let { active ->
            try {
                active.resume()
            } catch (error: CameraNotAvailableException) {
                Log.e(TAG, "camera not available", error)
                Toast.makeText(this, R.string.ar_not_supported, Toast.LENGTH_LONG).show()
                finish()
            }
        }
        surfaceView.onResume()
    }

    override fun onPause() {
        super.onPause()
        surfaceView.onPause()
        session?.pause()
        displayRotationHelper.onPause()
        link?.stop()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopEverything()
        qrScanner.close()
        followDetector.close()
        session?.close()
        session = null
        link?.close()
        link = null
    }

    private fun stopEverything() {
        drivingArmed = false
        executor?.stop()
        link?.stop()
    }

    // ------------------------------------------------------------------ ARCore

    private fun ensureArCore(): Boolean {
        return try {
            when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    installRequested = true
                    false
                }
                ArCoreApk.InstallStatus.INSTALLED -> true
            }
        } catch (error: Exception) {
            Log.e(TAG, "ARCore is not available", error)
            Toast.makeText(this, R.string.ar_not_supported, Toast.LENGTH_LONG).show()
            false
        }
    }

    private fun createSession() {
        val map = mapData ?: return
        try {
            val active = Session(this)
            val config = Config(active)
            config.focusMode = Config.FocusMode.AUTO
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
            config.lightEstimationMode = Config.LightEstimationMode.DISABLED
            config.depthMode = Config.DepthMode.DISABLED
            val database = buildMarkerDatabase(active, map)
            if (database != null) {
                config.augmentedImageDatabase = database
            }
            active.configure(config)
            session = active
        } catch (error: Exception) {
            Log.e(TAG, "could not create the AR session", error)
            Toast.makeText(this, R.string.ar_not_supported, Toast.LENGTH_LONG).show()
            finish()
        }
    }

    private fun buildMarkerDatabase(active: Session, map: MapData): AugmentedImageDatabase? {
        val database = AugmentedImageDatabase(active)
        var added = 0
        for (marker in map.markers) {
            val bitmap = try {
                assets.open("markers/" + marker.arImage + ".png").use { stream ->
                    BitmapFactory.decodeStream(stream)
                }
            } catch (error: Exception) {
                Log.w(TAG, "marker sheet missing for " + marker.id, error)
                null
            } ?: continue
            database.addImage(marker.id, bitmap, marker.sizeM.toFloat())
            added += 1
        }
        if (added == 0) return null
        Log.i(TAG, "augmented image database holds " + added + " marker sheets")
        return database
    }

    // --------------------------------------------------------------- renderer

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.05f, 0.07f, 0.1f, 1.0f)
        backgroundRenderer.createOnGlThread(this)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        displayRotationHelper.onSurfaceChanged(width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        val active = session
        if (active == null) {
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
            return
        }
        displayRotationHelper.updateSessionIfNeeded(active)
        try {
            active.setCameraTextureName(backgroundRenderer.cameraTextureId)
        } catch (error: Exception) {
            Log.w(TAG, "camera texture not ready", error)
            return
        }

        val frame = try {
            active.update()
        } catch (error: CameraNotAvailableException) {
            Log.w(TAG, "camera is not available", error)
            return
        }

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val tracking = frame.camera.trackingState == TrackingState.TRACKING
        if (!tracking && !followMode) {
            // The pose is not usable this frame: hold the wheels until it recovers.
            // Follow mode only needs the camera image, so it keeps running.
            link?.stop()
            return
        }
        backgroundRenderer.draw(frame)
        onArFrame(active, frame, frame.timestamp / 1_000_000_000.0)
    }

    // -------------------------------------------------------------- nav logic

    private fun onArFrame(active: Session, frame: Frame, nowS: Double) {
        val map = mapData ?: return
        val pose = estimator ?: return
        val cameraTransform = RigidTransform.fromPose(frame.camera.pose)
        val devicePose = MarkerGeometry.deviceInAr(cameraTransform)
        val dtS = if (lastFrameTimeS <= 0.0) 0.0 else (nowS - lastFrameTimeS).coerceIn(0.0, 0.5)
        lastFrameTimeS = nowS

        updateFloorHeight(active)

        // 1. image anchors: precise and available every frame while in view.
        var fix: Triple<String, Pose2D, Pose2D>? = null
        val expected = executor?.expectedMarkerId
        for (image in active.getAllTrackables(AugmentedImage::class.java)) {
            if (image.trackingState != TrackingState.TRACKING) continue
            val markerId = runCatching { map.marker(image.name).id }.getOrNull() ?: continue
            val alreadyAimed = fix != null && expected != null && fix.first == expected
            if (alreadyAimed && markerId != expected) continue
            val markerPose = MarkerGeometry.markerInArFromImagePose(RigidTransform.fromPose(image.centerPose))
            fix = Triple(markerId, markerPose, devicePose)
            knownFloorY = image.centerPose.translation[1].toDouble()
            if (markerId == expected) break
        }

        // 2. QR fallback: decodes the printed payload when the image tracker is cold.
        var detection = qrScanner.detections.poll()
        while (detection != null) {
            val next = qrScanner.detections.poll()
            if (next == null) {
                val marker = map.markerForPayload(detection.rawValue)
                if (marker != null) {
                    val markerPose = MarkerGeometry.markerPoseFromQuad(
                        corners = detection.corners,
                        intrinsics = intrinsicsFor(frame, detection),
                        cameraPose = detection.cameraPose,
                        floorY = knownFloorY,
                        ordered = true,
                        deviceYawRad = detection.deviceInAr.yawRad,
                    )
                    if (markerPose != null && (fix == null || marker.id == expected)) {
                        fix = Triple(marker.id, markerPose, detection.deviceInAr)
                    }
                }
            }
            detection = next
        }

        if (fix != null) {
            applyFix(fix.first, fix.second, fix.third, nowS)
        }

        // 3. ask for another decode now and then; the camera image is expensive.
        val cameraIntervalS = if (followMode) FOLLOW_INTERVAL_S else QR_INTERVAL_S
        if (nowS - lastCameraRequestS > cameraIntervalS) {
            lastCameraRequestS = nowS
            if (followMode) {
                requestFollowBox(frame, nowS)
            } else {
                requestQrDecode(frame, cameraTransform, devicePose, nowS)
            }
        }

        // 4. either the follow controller or the executor drives the robot.
        val routeExecutor = executor
        if (followMode) {
            if (drivingArmed) {
                tickFollow(nowS)
            }
        } else if (routeExecutor != null && drivingArmed) {
            val status = routeExecutor.tick(nowS, dtS)
            lastStatus = status
            if (status.state == ExecutorState.ARRIVED || status.state == ExecutorState.FAILED) {
                drivingArmed = false
            }
        }

        overlayView.updatePose(pose.pose)
        overlayView.setExpectedMarker(routeExecutor?.expectedMarkerId)
        updateUi(nowS)
    }

    private fun applyFix(markerId: String, markerPose: Pose2D, devicePose: Pose2D, nowS: Double) {
        val pose = estimator ?: return
        val observation = ArObservation(markerId, markerPose, devicePose, nowS)
        if (!fixIsPlausible(observation)) return
        pose.align(observation)
        executor?.noteMarker(markerId)
        overlayView.noteMarkerFix(markerId)
    }

    /** Reject a fix that would teleport the robot; the QR estimate can be rough. */
    private fun fixIsPlausible(observation: ArObservation): Boolean {
        val pose = estimator ?: return false
        val transform = pose.mapFromAr ?: return true
        val current = pose.pose ?: return true
        val predicted = transform.compose(observation.deviceInAr)
        return current.distanceTo(predicted) <= MAX_FIX_JUMP_M
    }

    private fun requestQrDecode(
        frame: Frame,
        cameraTransform: RigidTransform,
        devicePose: Pose2D,
        nowS: Double,
    ) {
        val image = try {
            frame.acquireCameraImage()
        } catch (error: NotYetAvailableException) {
            return
        } catch (error: Exception) {
            Log.w(TAG, "cannot grab the camera image", error)
            return
        }
        qrScanner.process(
            image = image,
            cameraPose = cameraTransform,
            devicePose = devicePose,
            cameraImageRotationDegrees = displayRotationHelper.cameraImageRotationDegrees(sensorOrientationDegrees),
            timestampS = nowS,
        )
    }

    /** One detection per frame goes to the follow controller; see follow.py. */
    private fun requestFollowBox(frame: Frame, nowS: Double) {
        val image = try {
            frame.acquireCameraImage()
        } catch (error: NotYetAvailableException) {
            return
        } catch (error: Exception) {
            Log.w(TAG, "cannot grab the camera image", error)
            return
        }
        followDetector.process(image, nowS)
    }

    private fun tickFollow(nowS: Double) {
        val robotLink = link ?: return
        val ageS = nowS - followDetector.latestAtS
        val box = followDetector.latestBox?.takeIf { ageS <= FollowController.BOX_TTL_S }
        val command = FollowController.followCommand(
            box = box,
            config = followConfig,
            sonarCm = robotLink.telemetry.sonarCm,
            secondsSinceSeen = ageS,
        )
        lastFollowCommand = command
        if (command.left == 0.0 && command.right == 0.0) {
            robotLink.stop()
        } else {
            robotLink.drive(command.left, command.right)
        }
    }

    /**
     * Intrinsics for the camera image. ARCore reports them for the image returned by
     * [Frame.acquireCameraImage]; a 60 degree field of view is the fallback when the
     * device refuses to hand them over.
     */
    private fun intrinsicsFor(frame: Frame, detection: QrDetection): CameraIntrinsics {
        val size = detection.imageWidth to detection.imageHeight
        if (sessionIntrinsicsSize == size) {
            sessionIntrinsics?.let { return it }
        }
        try {
            val intrinsics = frame.camera.imageIntrinsics
            val focal = intrinsics.focalLength
            val principal = intrinsics.principalPoint
            val dimensions = intrinsics.imageDimensions
            if (dimensions[0] > 0 && dimensions[1] > 0) {
                // The detection can come from a frame with a different image size.
                val scaleX = detection.imageWidth.toDouble() / dimensions[0].toDouble()
                val scaleY = detection.imageHeight.toDouble() / dimensions[1].toDouble()
                val values = CameraIntrinsics(
                    fx = focal[0].toDouble() * scaleX,
                    fy = focal[1].toDouble() * scaleY,
                    cx = principal[0].toDouble() * scaleX,
                    cy = principal[1].toDouble() * scaleY,
                    width = detection.imageWidth,
                    height = detection.imageHeight,
                )
                sessionIntrinsics = values
                sessionIntrinsicsSize = size
                return values
            }
        } catch (error: Throwable) {
            Log.i(TAG, "intrinsics unavailable, using a 60 degree field of view", error)
        }
        return CameraIntrinsics.fromHorizontalFov(detection.imageWidth, detection.imageHeight)
    }

    private fun updateFloorHeight(active: Session) {
        if (knownFloorY != null) return
        var best: Double? = null
        for (plane in active.getAllTrackables(Plane::class.java)) {
            if (plane.trackingState != TrackingState.TRACKING) continue
            if (plane.subsumedBy != null) continue
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            val height = plane.centerPose.translation[1].toDouble()
            if (best == null || height > best) best = height
        }
        knownFloorY = best
    }

    // ---------------------------------------------------------------------- UI

    private fun updateUi(nowS: Double) {
        if (nowS - lastUiUpdateS < UI_INTERVAL_S) return
        lastUiUpdateS = nowS
        val pose = estimator
        val status = lastStatus
        val poseText = pose?.pose?.let { current ->
            String.format(Locale.US, "x %.2f m  y %.2f m  yaw %.0f deg", current.x, current.y, current.yawDeg)
        } ?: "not localised yet"

        val fixText = if (followMode) {
            getString(R.string.follow_detail)
        } else if (pose != null && pose.aligned) {
            String.format(Locale.US, "last marker %s, %d AR fixes", pose.lastMarkerId ?: "-", pose.arUpdates)
        } else {
            getString(R.string.waiting_for_marker)
        }

        val distanceText = status?.let { current ->
            String.format(
                Locale.US,
                "remaining %.1f m, to waypoint %.1f m, drift %.1f m",
                current.distanceRemainingM,
                current.distanceToTargetM,
                current.driftM,
            )
        } ?: ""

        val sonar = link?.telemetry?.sonarCm
        val robotText = "robot: " + DemoState.describeLink() +
            (if (sonar != null) String.format(Locale.US, ", sonar %.0f cm", sonar) else "") +
            (if (link?.telemetry?.bumper != null) "  BUMPER!" else "")

        val headline = when {
            followMode && drivingArmed ->
                getString(R.string.follow_mode_label) + ": " +
                    (lastFollowCommand?.action ?: getString(R.string.follow_waiting))
            followMode -> getString(R.string.follow_ready)
            status != null -> status.state.label + ": " + status.message
            drivingArmed -> "driving"
            pose != null && pose.aligned -> getString(R.string.localised_tap_start)
            else -> getString(R.string.waiting_for_marker)
        }

        val remaining = status?.distanceRemainingM ?: route?.totalDistanceM ?: 0.0
        val guidance = if (followMode) {
            lastFollowCommand?.action ?: getString(R.string.follow_ready)
        } else {
            currentGuidance(remaining)
        }

        runOnUiThread {
            stateText.text = headline
            detailText.text = poseText + "\n" + fixText + "\n" + distanceText + "\n" + robotText
            guidanceText.text = guidance
            if (!startDrivingButton.isEnabled && !drivingArmed && (followMode || (pose?.aligned ?: false))) {
                startDrivingButton.isEnabled = true
            }
        }
    }

    private fun currentGuidance(remainingM: Double): String {
        val active = route ?: return ""
        val travelled = (active.totalDistanceM - remainingM).coerceAtLeast(0.0)
        var cumulative = 0.0
        for (step in guidanceSteps) {
            cumulative += step.distanceM
            if (cumulative >= travelled) return step.message
        }
        return guidanceSteps.lastOrNull()?.message ?: ""
    }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CAMERA && !hasCameraPermission()) {
            Toast.makeText(this, R.string.camera_permission_needed, Toast.LENGTH_LONG).show()
            finish()
        }
    }

    private companion object {
        const val TAG = "ArNavigation"
        const val REQUEST_CAMERA = 23
        const val QR_INTERVAL_S = 0.25
        const val FOLLOW_INTERVAL_S = 0.10
        const val UI_INTERVAL_S = 0.12
        const val MAX_FIX_JUMP_M = 3.0
        const val SENSOR_ORIENTATION_DEFAULT = 90
    }
}
