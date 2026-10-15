package com.openbene.arindoornav.nav

import com.openbene.arindoornav.ar.Planar
import com.openbene.arindoornav.robot.RobotLink
import kotlin.math.abs

data class NavPoint(val name: String, val pose: Planar)
enum class WaypointPhase { IDLE, ALIGN_LINE, DRIVE_LINE, ALIGN_NODE, WAITING, ARRIVED, INTERRUPTED }

/** iOS WaypointExecutor behaviour; ARCore camera poses are the only motion input. */
class WaypointExecutor(private val points: List<NavPoint>, private val link: RobotLink, val pwm: PwmSettings) {
    var phase = WaypointPhase.IDLE; private set
    var targetIndex = 1; private set
    var message = "请先识别锚点，再将机器人放回采集起点。"; private set
    var distanceRemainingM = 0.0; private set
    private var nextPhase: WaypointPhase? = null
    private var resumeAt = 0.0
    private var waitReason = ""
    val active get() = phase in listOf(WaypointPhase.ALIGN_LINE, WaypointPhase.DRIVE_LINE,
        WaypointPhase.ALIGN_NODE, WaypointPhase.WAITING)

    fun start(pose: Planar) {
        stop()
        require(points.size >= 2 && pwm.valid) { "请先采集起点及至少一个节点。" }
        require(points.all { valid(it.pose) }) { "航线中包含无效位置或朝向。" }
        require(valid(pose) && pose.distanceTo(points.first().pose) <= 0.30) { "请回到采集起点 30 cm 范围内。" }
        targetIndex = 1
        phase = WaypointPhase.ALIGN_LINE
        message = "准备转向第一段航线。"
    }

    fun stop(reason: String = "已停车；重新执行请回到起点。") {
        link.stop(); nextPhase = null
        phase = WaypointPhase.INTERRUPTED
        message = reason
    }

    fun tick(pose: Planar?, tracking: Boolean, available: Boolean, nowS: Double) {
        if (!active) return
        if (!nowS.isFinite()) { stop("计时不可用，已停车。"); return }
        if (!tracking || pose == null || !valid(pose)) { stop("定位跟踪不可用，已停车。恢复后回起点重新开始。"); return }
        if (!available) { stop("蓝牙断开，已停车。"); return }
        if (link.telemetry.bumper != null) { stop("检测到碰撞，已停车。"); return }
        if (phase == WaypointPhase.WAITING) {
            link.stop()
            if (nowS < resumeAt) { message = "$waitReason；停车等待 %.1f 秒。".format(resumeAt - nowS); return }
            phase = nextPhase ?: return
            nextPhase = null
        }
        val target = points.getOrNull(targetIndex) ?: run { finish(); return }
        val distance = pose.distanceTo(target.pose)
        distanceRemainingM = distance + points.drop(targetIndex).zipWithNext().sumOf { (a, b) -> a.pose.distanceTo(b.pose) }
        when (phase) {
            WaypointPhase.ALIGN_LINE -> {
                if (distance <= 0.30) { waitBefore(WaypointPhase.ALIGN_NODE, nowS, "已在节点位置，准备调整朝向"); return }
                val error = pose.headingErrorTo(target.pose)
                message = "转向 ${target.name}，方向误差 %.1f°".format(Math.toDegrees(error))
                if (abs(Math.toDegrees(error)) <= 3) waitBefore(WaypointPhase.DRIVE_LINE, nowS, "方向已对准，准备直行")
                else rotate(error)
            }
            WaypointPhase.DRIVE_LINE -> {
                if (distance <= 0.30) { waitBefore(WaypointPhase.ALIGN_NODE, nowS, "已到达 ${target.name}，准备调整朝向"); return }
                val error = pose.headingErrorTo(target.pose)
                if (abs(Math.toDegrees(error)) > 6) { waitBefore(WaypointPhase.ALIGN_LINE, nowS, "暂停直行，准备修正方向"); return }
                val speed = pwm.drive / 255.0
                val steer = (1.6 * error).coerceIn(-1.0, 1.0)
                link.drive(speed * (1 - steer), speed * (1 + steer))
                message = "直行至 ${target.name}，剩余 %.2f m".format(distance)
            }
            WaypointPhase.ALIGN_NODE -> {
                if (distance > 0.40) { waitBefore(WaypointPhase.ALIGN_LINE, nowS, "位置超出到点范围，准备重新对准"); return }
                val error = Planar.wrapRad(target.pose.yawRad - pose.yawRad)
                message = "${target.name} 朝向误差 %.1f°".format(Math.toDegrees(error))
                if (abs(Math.toDegrees(error)) <= 5) {
                    link.stop()
                    if (targetIndex == points.lastIndex) finish()
                    else { targetIndex++; waitBefore(WaypointPhase.ALIGN_LINE, nowS, "节点朝向已调整，准备下一段") }
                } else rotate(error)
            }
            else -> link.stop()
        }
    }

    private fun rotate(error: Double) {
        val value = if (error >= 0) pwm.leftTurn / 255.0 else -pwm.rightTurn / 255.0
        link.drive(-value, value)
    }

    private fun waitBefore(next: WaypointPhase, nowS: Double, reason: String) {
        link.stop(); phase = WaypointPhase.WAITING; nextPhase = next
        resumeAt = nowS + 2; waitReason = reason
        message = "$reason；停车等待 2 秒。"
    }

    private fun finish() {
        link.stop(); nextPhase = null; phase = WaypointPhase.ARRIVED
        distanceRemainingM = 0.0; message = "航线完成，末节点位置与朝向已到达。"
    }
    private fun valid(p: Planar) = p.x.isFinite() && p.y.isFinite() && p.yawRad.isFinite()
}
