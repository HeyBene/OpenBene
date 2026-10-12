package com.openbene.anchornav.ar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import com.openbene.anchornav.nav.MapData
import com.openbene.anchornav.nav.Pose2D
import com.openbene.anchornav.nav.Route
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * A small top down view of the demo floor: graph edges, the active route, the
 * markers that were used for localisation and the estimated robot pose.
 */
class RouteOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private var mapData: MapData? = null
    private var route: Route? = null
    private var pose: Pose2D? = null
    private var expectedMarkerId: String? = null
    private val trail = ArrayList<Pose2D>()
    private val fixedMarkers = LinkedHashSet<String>()

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#CC10233B") }
    private val edgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#668FB3C8")
        style = Paint.Style.STROKE
        strokeWidth = 6f
        strokeCap = Paint.Cap.ROUND
    }
    private val routePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF14B8A6")
        style = Paint.Style.STROKE
        strokeWidth = 10f
        strokeCap = Paint.Cap.ROUND
    }
    private val trailPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#99E2E8F0")
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }
    private val markerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FFF59E0B")
        style = Paint.Style.STROKE
        strokeWidth = 5f
    }
    private val fixedMarkerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF14B8A6")
        style = Paint.Style.FILL
    }
    private val locationPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val robotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#FF22D3EE") }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 22f
    }
    private val frame = RectF()
    private val path = Path()

    fun bind(map: MapData) {
        mapData = map
        trail.clear()
        fixedMarkers.clear()
        invalidate()
    }

    fun setRoute(value: Route?) {
        route = value
        invalidate()
    }

    fun setExpectedMarker(markerId: String?) {
        expectedMarkerId = markerId
        invalidate()
    }

    fun noteMarkerFix(markerId: String) {
        fixedMarkers.add(markerId)
        invalidate()
    }

    fun updatePose(value: Pose2D?) {
        pose = value
        if (value != null) {
            val last = trail.lastOrNull()
            if (last == null || last.distanceTo(value) > 0.08) {
                trail.add(value)
                if (trail.size > 600) trail.removeAt(0)
            }
        }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val map = mapData ?: return

        val panelSize = min(width * 0.55f, height * 0.34f)
        val padding = 16f
        val left = width - panelSize - padding
        val top = height * 0.22f
        frame.set(left, top, left + panelSize, top + panelSize)

        canvas.drawRoundRect(frame, 24f, 24f, fillPaint)
        canvas.save()
        canvas.clipRect(frame)

        val points = ArrayList<Pose2D>()
        map.locations.forEach { points.add(it.pose) }
        map.markers.forEach { points.add(it.pose) }
        map.edges.forEach { edge -> points.addAll(edge.path) }
        if (points.isEmpty()) {
            canvas.restore()
            return
        }
        val minX = points.minOf { it.x }
        val maxX = points.maxOf { it.x }
        val minY = points.minOf { it.y }
        val maxY = points.maxOf { it.y }
        val spanX = max(maxX - minX, 0.5)
        val spanY = max(maxY - minY, 0.5)
        val inner = panelSize - 2f * padding
        val scale = min(inner / spanX.toFloat(), inner / spanY.toFloat())
        val offsetX = frame.left + padding + (inner - spanX.toFloat() * scale) * 0.5f
        val offsetY = frame.top + padding + (inner - spanY.toFloat() * scale) * 0.5f

        fun screenX(x: Double): Float = offsetX + (x - minX).toFloat() * scale
        fun screenY(y: Double): Float = offsetY + (maxY - y).toFloat() * scale

        // graph edges
        map.edges.forEach { edge ->
            path.reset()
            edge.path.forEachIndexed { index, point ->
                if (index == 0) path.moveTo(screenX(point.x), screenY(point.y))
                else path.lineTo(screenX(point.x), screenY(point.y))
            }
            canvas.drawPath(path, edgePaint)
        }

        // trail of estimated poses
        if (trail.size > 1) {
            path.reset()
            trail.forEachIndexed { index, point ->
                if (index == 0) path.moveTo(screenX(point.x), screenY(point.y))
                else path.lineTo(screenX(point.x), screenY(point.y))
            }
            canvas.drawPath(path, trailPaint)
        }

        // active route
        route?.let { active ->
            path.reset()
            active.polyline.forEachIndexed { index, point ->
                if (index == 0) path.moveTo(screenX(point.x), screenY(point.y))
                else path.lineTo(screenX(point.x), screenY(point.y))
            }
            canvas.drawPath(path, routePaint)
        }

        // locations
        map.locations.forEach { location ->
            val cx = screenX(location.pose.x)
            val cy = screenY(location.pose.y)
            canvas.drawCircle(cx, cy, 6f, locationPaint)
            canvas.drawText(location.name, cx + 10f, cy - 8f, labelPaint)
        }

        // markers
        map.markers.forEach { marker ->
            val cx = screenX(marker.pose.x)
            val cy = screenY(marker.pose.y)
            val half = 12f
            canvas.save()
            canvas.rotate((-marker.pose.yawDeg).toFloat(), cx, cy)
            canvas.drawRect(cx - half, cy - half, cx + half, cy + half, markerPaint)
            canvas.restore()
            if (fixedMarkers.contains(marker.id) || marker.id == expectedMarkerId) {
                canvas.drawCircle(cx, cy, 5f, fixedMarkerPaint)
            }
        }

        // robot
        pose?.let { current ->
            val cx = screenX(current.x)
            val cy = screenY(current.y)
            val heading = -current.yawRad
            val size = 22f
            val tipX = cx + size * cos(heading).toFloat()
            val tipY = cy + size * sin(heading).toFloat()
            val leftX = cx + size * 0.7f * cos(heading + 2.5).toFloat()
            val leftY = cy + size * 0.7f * sin(heading + 2.5).toFloat()
            val rightX = cx + size * 0.7f * cos(heading - 2.5).toFloat()
            val rightY = cy + size * 0.7f * sin(heading - 2.5).toFloat()
            path.reset()
            path.moveTo(tipX, tipY)
            path.lineTo(leftX, leftY)
            path.lineTo(rightX, rightY)
            path.close()
            canvas.drawPath(path, robotPaint)
        }

        canvas.restore()
    }
}
