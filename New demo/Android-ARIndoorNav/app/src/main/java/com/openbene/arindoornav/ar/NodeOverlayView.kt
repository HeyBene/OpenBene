package com.openbene.arindoornav.ar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * Draws the recorded chain over the camera image: one sphere per node, a line to
 * the next node and an arrow head on every segment - the same three things the
 * original ARIndoorNav added to its AR scene. The nodes are projected with the
 * ARCore camera matrices instead of being rendered in OpenGL, which keeps the
 * whole overlay in one small file.
 */
class NodeOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private var nodes: List<FloatArray> = emptyList()
    private var viewProjection: FloatArray? = null
    private var focalPx: Float = 0f
    private var currentIndex: Int = -1
    private var anchorName: String? = null
    private val screen = FloatArray(3)
    private val arrowPath = Path()

    private val spherePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val intermediatePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF2F6FED")
    }
    private val currentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF14B8A6")
        style = Paint.Style.STROKE
        strokeWidth = 6f
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E6FFFFFF")
        style = Paint.Style.STROKE
        strokeWidth = 6f
        strokeCap = Paint.Cap.ROUND
    }
    private val arrowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E6FFFFFF")
        style = Paint.Style.FILL
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 30f
        textAlign = Paint.Align.CENTER
        setShadowLayer(6f, 0f, 2f, Color.BLACK)
    }
    private val anchorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#CCFFFFFF")
        textSize = 26f
        setShadowLayer(6f, 0f, 2f, Color.BLACK)
    }

    /** Nodes are AR world positions; call from any thread. */
    fun update(
        nodes: List<FloatArray>,
        viewProjection: FloatArray,
        focalPx: Float,
        currentIndex: Int,
        anchorName: String?,
    ) {
        this.nodes = nodes
        this.viewProjection = viewProjection
        this.focalPx = focalPx
        this.currentIndex = currentIndex
        this.anchorName = anchorName
        invalidate()
    }

    fun clear() {
        nodes = emptyList()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val matrix = viewProjection ?: return
        if (nodes.isEmpty()) return

        val projected = ArrayList<FloatArray?>(nodes.size)
        for (node in nodes) {
            val visible = ArMath.project(matrix, node, width, height, screen)
            projected.add(if (visible) floatArrayOf(screen[0], screen[1], screen[2]) else null)
        }

        for (index in 0 until nodes.size - 1) {
            val from = projected[index] ?: continue
            val to = projected[index + 1] ?: continue
            canvas.drawLine(from[0], from[1], to[0], to[1], linePaint)
            drawArrowHead(canvas, from, to)
        }

        for (index in projected.indices) {
            val point = projected[index] ?: continue
            val radius = (focalPx * NODE_RADIUS_M / point[2]).coerceIn(6f, 120f)
            val end = index == 0 || index == projected.size - 1
            canvas.drawCircle(point[0], point[1], radius, if (end) spherePaint else intermediatePaint)
            if (index == currentIndex) {
                canvas.drawCircle(point[0], point[1], radius + 10f, currentPaint)
            }
            canvas.drawText(label(index, projected.size), point[0], point[1] - radius - 12f, labelPaint)
        }

        anchorName?.let { canvas.drawText("anchor: " + it, 24f, height - 24f, anchorPaint) }
    }

    private fun label(index: Int, count: Int): String = when {
        index == 0 -> "start"
        index == count - 1 -> "dest"
        else -> index.toString()
    }

    private fun drawArrowHead(canvas: Canvas, from: FloatArray, to: FloatArray) {
        val middleX = (from[0] + to[0]) * 0.5f
        val middleY = (from[1] + to[1]) * 0.5f
        val angle = atan2((to[1] - from[1]).toDouble(), (to[0] - from[0]).toDouble())
        val size = 30.0
        arrowPath.reset()
        arrowPath.moveTo(
            (middleX + size * cos(angle)).toFloat(),
            (middleY + size * sin(angle)).toFloat(),
        )
        arrowPath.lineTo(
            (middleX + size * cos(angle + 2.5)).toFloat(),
            (middleY + size * sin(angle + 2.5)).toFloat(),
        )
        arrowPath.lineTo(
            (middleX + size * cos(angle - 2.5)).toFloat(),
            (middleY + size * sin(angle - 2.5)).toFloat(),
        )
        arrowPath.close()
        canvas.drawPath(arrowPath, arrowPaint)
    }

    private companion object {
        /** Sphere radius of the original ARIndoorNav: 5 cm. */
        const val NODE_RADIUS_M = 0.05f
    }
}
