package com.openbene.arindoornav.ar

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.ArCoreApk
import com.google.ar.core.AugmentedImage
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.openbene.arindoornav.AppState
import com.openbene.arindoornav.R
import com.openbene.arindoornav.RouteStore
import com.openbene.arindoornav.model.RouteNode
import com.openbene.arindoornav.model.StoredRoute
import com.openbene.arindoornav.model.TYPE_DESTINATION
import com.openbene.arindoornav.model.TYPE_INTERMEDIATE
import com.openbene.arindoornav.model.TYPE_START
import com.openbene.arindoornav.nav.DriverConfig
import com.openbene.arindoornav.nav.FollowCommand
import com.openbene.arindoornav.nav.FollowConfig
import com.openbene.arindoornav.nav.FollowController
import com.openbene.arindoornav.nav.NodeDriver
import com.openbene.arindoornav.robot.PersonBoxDetector
import com.openbene.arindoornav.robot.RobotLink
import java.util.Locale
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * The AR screen, with the three modes the original ARIndoorNav work is split into:
 *
 * * capture: the first tracked sheet becomes the world origin, Add records the
 *   current camera position as the next node of the chain, End closes the chain and
 *   Save writes it to the routes file;
 * * navigate: the same sheet is scanned again, the chain is rebuilt from the stored
 *   offsets and the OpenBot can be driven along it;
 * * follow: OpenBot tracking, the robot drives towards the person in front of it.
 *
 * The anchor is locked to the first tracked sheet of the session and is never
 * re-locked, exactly like the original: one anchor, then ARCore tracking only.
 */
class ArRouteActivity : AppCompatActivity(), GLSurfaceView.Renderer {

    private lateinit var surfaceView: GLSurfaceView
    private lateinit var overlayView: NodeOverlayView
    private lateinit var stateText: TextView
    private lateinit var detailText: TextView
    private lateinit var guidanceText: TextView
    private lateinit var captureRow: LinearLayout
    private lateinit var addButton: Button
    private lateinit var undoButton: Button
    private lateinit var endButton: Button
    private lateinit var saveButton: Button
    private lateinit var startButton: Button

    private lateinit var displayRotationHelper: DisplayRotationHelper
    private lateinit var store: RouteStore
    private val backgroundRenderer = CameraBackgroundRenderer()
    private val followDetector = PersonBoxDetector()
    private val followConfig = FollowConfig.FACE_BOX
    private val driverConfig = DriverConfig()

    private var mode = MODE_CAPTURE
    private var destination = ""
    private var storedRoute: StoredRoute? = null

    private var session: Session? = null
    private var installRequested = false
    private var link: RobotLink? = null
    private var sensorOrientationDegrees = 0

    /** The anchor of this AR session: the pose of the first sheet that was tracked. */
    private var anchorPose: Pose? = null
    private var anchorName: String? = null

    /** Capture state: the chain as it is being recorded, in the anchor frame. */
    private val captured = ArrayList<RouteNode>()
    private val anchorPoints = ArrayList<FloatArray>()
    private var startNodeSet = false
    private var destinationSet = false

    /**
     * Positions of the chain in AR world coordinates. Rebuilt as a fresh list when
     * the chain changes, so the GL thread always reads a complete one.
     */
    @Volatile
    private var worldPoints: List<FloatArray> = emptyList()

    private var lastCameraPose: Pose? = null
    private var lastPlanar: Planar? = null
    private var targetIndex = 0
    private var drivingArmed = false
    private var blocked = false
    private var driverAction = ""
    private var lastFollowCommand: FollowCommand? = null
    private var lastCameraRequestS = -10.0
    private var lastUiUpdateS = -10.0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ar_route)

        surfaceView = findViewById(R.id.surfaceView)
        overlayView = findViewById(R.id.nodeOverlayView)
        stateText = findViewById(R.id.stateText)
        detailText = findViewById(R.id.detailText)
        guidanceText = findViewById(R.id.guidanceText)
        captureRow = findViewById(R.id.captureRow)
        addButton = findViewById(R.id.addButton)
        undoButton = findViewById(R.id.undoButton)
        endButton = findViewById(R.id.endButton)
        saveButton = findViewById(R.id.saveButton)
        startButton = findViewById(R.id.startDrivingButton)
        val stopButton: Button = findViewById(R.id.stopButton)

        displayRotationHelper = DisplayRotationHelper(this)
        store = RouteStore(this)
        mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_CAPTURE
        destination = intent.getStringExtra(EXTRA_DESTINATION) ?: ""
        sensorOrientationDegrees = readSensorOrientation()

        if (mode == MODE_NAVIGATE) {
            val route = store.find(destination)
            if (route == null) {
                Toast.makeText(
                    this,
                    getString(R.string.route_load_failed, destination),
                    Toast.LENGTH_LONG,
                ).show()
                finish()
                return
            }
            storedRoute = route
        }

        link = AppState.createLink(this)

        addButton.setOnClickListener {
            recordNode(if (startNodeSet) TYPE_INTERMEDIATE else TYPE_START)
        }
        undoButton.setOnClickListener { undoLastNode() }
        endButton.setOnClickListener { recordNode(TYPE_DESTINATION) }
        saveButton.setOnClickListener { askForNameAndSave() }
        startButton.setOnClickListener { armDriving() }
        stopButton.setOnClickListener {
            stopEverything()
            finish()
        }

        captureRow.visibility = if (mode == MODE_CAPTURE) View.VISIBLE else View.GONE
        startButton.visibility = if (mode == MODE_CAPTURE) View.GONE else View.VISIBLE
        guidanceText.text = when (mode) {
            MODE_CAPTURE -> getString(R.string.capture_hint_need_anchor)
            MODE_FOLLOW -> getString(R.string.follow_ready)
            else -> getString(R.string.navigate_hint)
        }
        updateCaptureButtons()

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
        followDetector.close()
        session?.close()
        session = null
        link?.close()
        link = null
    }

    private fun stopEverything() {
        drivingArmed = false
        link?.stop()
    }

    // ------------------------------------------------------------------ ARCore

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

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
        try {
            val active = Session(this)
            val config = Config(active)
            config.focusMode = Config.FocusMode.AUTO
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            // Only image anchors are used, so plane finding and depth stay off.
            config.planeFindingMode = Config.PlaneFindingMode.DISABLED
            config.lightEstimationMode = Config.LightEstimationMode.DISABLED
            config.depthMode = Config.DepthMode.DISABLED
            AnchorSheets.buildDatabase(this, active)?.let { config.augmentedImageDatabase = it }
            active.configure(config)
            session = active
        } catch (error: Exception) {
            Log.e(TAG, "could not create the AR session", error)
            Toast.makeText(this, R.string.ar_not_supported, Toast.LENGTH_LONG).show()
            finish()
        }
    }

    /** Rotation of the back camera sensor, for the follow-mode detector. */
    private fun readSensorOrientation(): Int {
        return try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            for (id in manager.cameraIdList) {
                val characteristics = manager.getCameraCharacteristics(id)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                    return characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
                }
            }
            0
        } catch (error: Exception) {
            Log.w(TAG, "cannot read the sensor orientation", error)
            0
        }
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
        if (!tracking && mode != MODE_FOLLOW) {
            // The pose is not usable this frame: hold the wheels until it recovers.
            // Follow mode only needs the camera image, so it keeps running.
            link?.stop()
            return
        }
        backgroundRenderer.draw(frame)
        onArFrame(active, frame, frame.timestamp / 1_000_000_000.0)
    }

    // -------------------------------------------------------------- AR frame

    private fun onArFrame(active: Session, frame: Frame, nowS: Double) {
        if (frame.camera.trackingState == TrackingState.TRACKING) {
            lastCameraPose = frame.camera.pose
            lastPlanar = ArMath.planarOf(frame.camera.pose)
        }

        lockAnchorIfNeeded(active)

        if (mode == MODE_FOLLOW) {
            val interval = FOLLOW_INTERVAL_S
            if (nowS - lastCameraRequestS > interval) {
                lastCameraRequestS = nowS
                requestFollowBox(frame, nowS)
            }
            if (drivingArmed) tickFollow(nowS)
        } else if (mode == MODE_NAVIGATE && drivingArmed) {
            tickDrive()
        }

        val viewMatrix = FloatArray(16)
        val projectionMatrix = FloatArray(16)
        frame.camera.getViewMatrix(viewMatrix, 0)
        frame.camera.getProjectionMatrix(projectionMatrix, 0, 0.05f, 30.0f)
        overlayView.update(
            nodes = worldPoints,
            viewProjection = ArMath.multiply(projectionMatrix, viewMatrix),
            focalPx = ArMath.focalPixels(projectionMatrix, surfaceView.height),
            currentIndex = if (mode == MODE_NAVIGATE) targetIndex else -1,
            anchorName = anchorName,
        )
        updateUi(nowS)
    }

    /**
     * The first sheet that is tracked in this session becomes the world origin of
     * the chain. A second sheet is ignored, as in the original app.
     */
    private fun lockAnchorIfNeeded(active: Session) {
        if (anchorPose != null) return
        for (image in active.getAllTrackables(AugmentedImage::class.java)) {
            if (image.trackingState != TrackingState.TRACKING) continue
            val name = image.name ?: continue
            if (!AnchorSheets.isAnchor(name)) continue
            anchorPose = image.centerPose
            anchorName = name
            onAnchorLocked()
            return
        }
    }

    private fun onAnchorLocked() {
        if (mode == MODE_NAVIGATE) {
            rebuildChainFromRoute()
            targetIndex = 0
            guidanceText.text = getString(R.string.navigate_hint)
        }
        if (mode == MODE_CAPTURE) {
            updateCaptureButtons()
            guidanceText.text = getString(R.string.capture_hint_start)
        }
    }

    // --------------------------------------------------------------- capture

    private fun recordNode(type: String) {
        if (mode != MODE_CAPTURE || destinationSet) return
        val anchor = anchorPose
        if (anchor == null) {
            guidanceText.text = getString(R.string.capture_hint_need_anchor)
            return
        }
        val camera = lastCameraPose
        if (camera == null) {
            guidanceText.text = getString(R.string.waiting_for_tracking)
            return
        }

        // Camera pose in the anchor frame: the same quantity the original app took
        // from the ARKit session after it moved the world origin onto the sheet.
        val position = anchor.inverse().compose(camera).translation
        val previous = anchorPoints.lastOrNull()
        val node = if (previous == null) {
            RouteNode(type, position[0].toDouble(), position[1].toDouble(), position[2].toDouble())
        } else {
            RouteNode(
                type,
                (position[0] - previous[0]).toDouble(),
                (position[1] - previous[1]).toDouble(),
                (position[2] - previous[2]).toDouble(),
            )
        }
        captured.add(node)
        anchorPoints.add(floatArrayOf(position[0], position[1], position[2]))

        when (type) {
            TYPE_START -> startNodeSet = true
            TYPE_DESTINATION -> destinationSet = true
        }
        rebuildWorldPoints()
        updateCaptureButtons()
        guidanceText.text = if (destinationSet) {
            getString(R.string.capture_hint_ended)
        } else {
            getString(R.string.capture_hint_more)
        }
    }

    private fun undoLastNode() {
        if (mode != MODE_CAPTURE || captured.isEmpty()) return
        val removed = captured.removeAt(captured.size - 1)
        anchorPoints.removeAt(anchorPoints.size - 1)
        when (removed.type) {
            TYPE_START -> startNodeSet = false
            TYPE_DESTINATION -> destinationSet = false
        }
        rebuildWorldPoints()
        updateCaptureButtons()
        guidanceText.text = if (captured.isEmpty()) {
            getString(R.string.capture_hint_start)
        } else {
            getString(R.string.capture_hint_more)
        }
    }

    private fun updateCaptureButtons() {
        if (mode != MODE_CAPTURE) return
        val anchored = anchorPose != null
        addButton.isEnabled = anchored && !destinationSet
        endButton.isEnabled = anchored && startNodeSet && !destinationSet
        undoButton.isEnabled = anchored && captured.isNotEmpty()
        saveButton.isEnabled = destinationSet && captured.isNotEmpty()
    }

    private fun askForNameAndSave() {
        if (captured.isEmpty()) return
        val input = EditText(this)
        input.hint = getString(R.string.save_dialog_hint)
        input.setText(destination.ifEmpty { "route " + (store.load().size + 1) })
        AlertDialog.Builder(this)
            .setTitle(R.string.save_dialog_title)
            .setView(input)
            .setPositiveButton(android.R.string.ok) { _, _ -> saveRoute(input.text.toString().trim()) }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun saveRoute(name: String) {
        if (name.isEmpty()) return
        try {
            store.upsert(StoredRoute(name, anchorName ?: "", captured.toList()))
            Toast.makeText(this, getString(R.string.save_done, name), Toast.LENGTH_LONG).show()
            finish()
        } catch (error: Exception) {
            Toast.makeText(
                this,
                getString(R.string.save_failed, error.message ?: ""),
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    // -------------------------------------------------------------- navigate

    /**
     * Rebuilds the chain from the stored offsets: every node sits one recorded
     * offset away from the previous one, and the first one sits that far from the
     * anchor sheet. This is the original app's placement, offset by offset.
     */
    private fun rebuildChainFromRoute() {
        val route = storedRoute ?: return
        anchorPoints.clear()
        var accumulated = FloatArray(3)
        for (node in route.nodes) {
            accumulated = floatArrayOf(
                accumulated[0] + node.xOffset.toFloat(),
                accumulated[1] + node.yOffset.toFloat(),
                accumulated[2] + node.zOffset.toFloat(),
            )
            anchorPoints.add(accumulated.copyOf())
        }
        rebuildWorldPoints()
    }

    private fun rebuildWorldPoints() {
        val anchor = anchorPose
        if (anchor == null) {
            worldPoints = emptyList()
            return
        }
        worldPoints = anchorPoints.map { anchor.transformPoint(it) }
    }

    private fun armDriving() {
        if (mode == MODE_FOLLOW) {
            drivingArmed = true
            startButton.isEnabled = false
            guidanceText.text = getString(R.string.follow_armed)
            return
        }
        if (mode != MODE_NAVIGATE) return
        if (worldPoints.isEmpty()) {
            guidanceText.text = getString(R.string.navigate_hint)
            return
        }
        targetIndex = 0
        blocked = false
        drivingArmed = true
        startButton.isEnabled = false
        guidanceText.text = getString(R.string.navigate_hint)
    }

    private fun tickDrive() {
        val robotLink = link ?: return
        val pose = lastPlanar ?: return
        if (worldPoints.isEmpty()) return
        if (targetIndex >= worldPoints.size) {
            drivingArmed = false
            robotLink.stop()
            return
        }

        val target = ArMath.planarOfPoint(worldPoints[targetIndex])
        if (pose.distanceTo(target) <= driverConfig.arriveToleranceM) {
            robotLink.stop()
            if (targetIndex == worldPoints.size - 1) {
                drivingArmed = false
                startButton.isEnabled = true
                driverAction = "arrived at " + destination
                guidanceText.text = driverAction
            } else {
                targetIndex += 1
            }
            return
        }

        val command = NodeDriver.command(
            pose = pose,
            target = target,
            sonarCm = robotLink.telemetry.sonarCm,
            wasBlocked = blocked,
            config = driverConfig,
        )
        blocked = command.blocked
        driverAction = command.action
        if (command.left == 0.0 && command.right == 0.0) {
            robotLink.stop()
        } else {
            robotLink.drive(command.left, command.right)
        }
        guidanceText.text = String.format(
            Locale.US,
            "node %d/%d  %s",
            targetIndex + 1,
            worldPoints.size,
            command.action,
        )
    }

    // ---------------------------------------------------------------- follow

    /** One detection per request goes to the follow controller; see follow.py. */
    private fun requestFollowBox(frame: Frame, nowS: Double) {
        val image = try {
            frame.acquireCameraImage()
        } catch (error: NotYetAvailableException) {
            return
        } catch (error: Exception) {
            Log.w(TAG, "cannot grab the camera image", error)
            return
        }
        val rotation = displayRotationHelper.cameraImageRotationDegrees(sensorOrientationDegrees)
        followDetector.process(image, nowS, rotation)
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
        guidanceText.text = "follow mode: " + command.action
    }

    // -------------------------------------------------------------------- UI

    private fun updateUi(nowS: Double) {
        if (nowS - lastUiUpdateS < UI_INTERVAL_S) return
        lastUiUpdateS = nowS

        val anchor = anchorName
        stateText.text = when {
            mode == MODE_FOLLOW -> getString(R.string.state_following)
            anchor == null -> getString(R.string.state_looking_for_anchor)
            mode == MODE_CAPTURE -> getString(R.string.state_capturing, anchor)
            else -> getString(R.string.state_navigating, destination)
        }

        val builder = StringBuilder()
        builder.append("anchors: ").append(AnchorSheets.describe()).append('\n')
        builder.append("link: ").append(AppState.describeLink()).append('\n')
        when (mode) {
            MODE_CAPTURE -> builder.append("nodes recorded: ").append(captured.size)
            MODE_NAVIGATE -> {
                builder.append("chain: ").append(worldPoints.size).append(" nodes")
                if (drivingArmed) {
                    builder.append(", target ").append(targetIndex + 1)
                    lastPlanar?.let { pose ->
                        if (targetIndex < worldPoints.size) {
                            val distance = pose.distanceTo(ArMath.planarOfPoint(worldPoints[targetIndex]))
                            builder.append(String.format(Locale.US, ", %.2f m", distance))
                        }
                    }
                }
            }
            MODE_FOLLOW -> {
                val command = lastFollowCommand
                builder.append("follow: ").append(command?.action ?: getString(R.string.follow_waiting))
            }
        }
        (link as? com.openbene.arindoornav.robot.MockRobotLink)?.let { mock ->
            builder.append(String.format(Locale.US, "\nwheels: %.2f / %.2f", mock.lastLeft, mock.lastRight))
        }
        detailText.text = builder.toString()
    }

    companion object {
        const val EXTRA_MODE = "mode"
        const val EXTRA_DESTINATION = "destination"
        const val MODE_CAPTURE = "capture"
        const val MODE_NAVIGATE = "navigate"
        const val MODE_FOLLOW = "follow"

        private const val TAG = "ArRouteActivity"
        private const val REQUEST_CAMERA = 23
        private const val FOLLOW_INTERVAL_S = 0.2
        private const val UI_INTERVAL_S = 0.25

        fun intent(context: Context, mode: String, destination: String = ""): Intent =
            Intent(context, ArRouteActivity::class.java)
                .putExtra(EXTRA_MODE, mode)
                .putExtra(EXTRA_DESTINATION, destination)
    }
}
