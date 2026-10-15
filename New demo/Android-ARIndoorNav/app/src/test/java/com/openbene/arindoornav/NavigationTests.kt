package com.openbene.arindoornav

import com.openbene.arindoornav.ar.*
import com.openbene.arindoornav.model.*
import com.openbene.arindoornav.nav.*
import com.openbene.arindoornav.robot.*
import org.junit.Assert.*
import org.junit.Test

private class RecordingLink : RobotLink {
    override val telemetry = Telemetry(connected = true)
    var frame = "c0,0"
    override fun drive(left: Double, right: Double) { frame = OpenBotProtocol.ctrlCmd(left, right).toString(Charsets.US_ASCII).trim() }
    override fun stop() { frame = "c0,0" }
    override fun close() { stop(); telemetry.connected = false }
}

class NavigationTests {
    private val start = Planar(0.0, 0.0, 0.0)
    private val settings = PwmSettings(drive = 160, leftTurn = 140, rightTurn = 180)
    private fun route(link: RobotLink, endYaw: Double = Math.PI / 2) = WaypointExecutor(listOf(
        NavPoint("起点", start), NavPoint("节点1", Planar(2.0, 0.0, endYaw)),
        NavPoint("节点2", Planar(2.0, 2.0, Math.PI))), link, settings)
    private fun tick(e: WaypointExecutor, pose: Planar?, t: Double, tracking: Boolean = true, available: Boolean = true) = e.tick(pose, tracking, available, t)

    @Test fun independentLeftTurnPwm() {
        val l = RecordingLink(); val e = route(l); e.start(start.copy(yawRad = -1.0)); tick(e, start.copy(yawRad = -1.0), 0.0)
        assertEquals("c-140,140", l.frame); assertEquals(WaypointPhase.ALIGN_LINE, e.phase)
    }
    @Test fun independentRightTurnPwm() {
        val l = RecordingLink(); val e = route(l); e.start(start.copy(yawRad = 1.0)); tick(e, start.copy(yawRad = 1.0), 0.0)
        assertEquals("c180,-180", l.frame)
    }
    @Test fun waitsTwoSecondsBetweenAlignAndDrive() {
        val l = RecordingLink(); val e = route(l); e.start(start); tick(e, start, 10.0)
        assertEquals(WaypointPhase.WAITING, e.phase); assertEquals("c0,0", l.frame)
        tick(e, start, 11.999); assertEquals("c0,0", l.frame)
        tick(e, start, 12.0); assertEquals(WaypointPhase.DRIVE_LINE, e.phase); assertEquals("c160,160", l.frame)
    }
    @Test fun arrivalAndHeadingAndNextNodeHavePauses() {
        val l = RecordingLink(); val e = route(l); e.start(start)
        tick(e, start, 0.0); tick(e, start, 2.0)
        val atFirst = Planar(2.0, 0.0, 0.0)
        tick(e, atFirst, 3.0); assertEquals(WaypointPhase.WAITING, e.phase)
        tick(e, atFirst, 4.99); assertEquals("c0,0", l.frame)
        tick(e, atFirst, 5.0); assertEquals(WaypointPhase.ALIGN_NODE, e.phase); assertEquals("c-140,140", l.frame)
        val firstAligned = atFirst.copy(yawRad = Math.PI / 2)
        tick(e, firstAligned, 6.0); assertEquals(2, e.targetIndex); assertEquals(WaypointPhase.WAITING, e.phase)
        tick(e, firstAligned, 7.99); assertEquals("c0,0", l.frame)
        tick(e, firstAligned, 8.0); assertEquals(WaypointPhase.WAITING, e.phase) // next line already aligned; drive gets its own pause
        tick(e, firstAligned, 10.0); assertEquals("c160,160", l.frame)
        val atLast = Planar(2.0, 2.0, Math.PI / 2)
        tick(e, atLast, 11.0); tick(e, atLast, 13.0); assertEquals("c-140,140", l.frame)
        tick(e, atLast.copy(yawRad = Math.PI), 14.0)
        assertEquals(WaypointPhase.ARRIVED, e.phase); assertEquals("c0,0", l.frame)
        assertEquals(0.0, e.distanceRemainingM, 1e-9)
    }
    @Test fun waitingRechecksCurrentHeadingBeforeMoving() {
        val l = RecordingLink(); val e = route(l); e.start(start); tick(e, start, 0.0)
        tick(e, start.copy(yawRad = 1.0), 2.0)
        assertEquals(WaypointPhase.WAITING, e.phase); assertEquals("c0,0", l.frame)
        tick(e, start.copy(yawRad = 1.0), 4.0); assertEquals("c180,-180", l.frame)
    }
    @Test fun stopCancelsPendingTransition() {
        val l = RecordingLink(); val e = route(l); e.start(start); tick(e, start, 0.0); e.stop(); tick(e, start, 20.0)
        assertEquals(WaypointPhase.INTERRUPTED, e.phase); assertEquals("c0,0", l.frame)
    }
    @Test fun trackingLossNeverAutoResumes() {
        val l = RecordingLink(); val e = route(l); e.start(start); tick(e, start, 0.0)
        tick(e, null, 1.0, tracking = false); tick(e, start, 10.0)
        assertFalse(e.active); assertEquals("c0,0", l.frame)
    }
    @Test fun disconnectCancelsPause() {
        val l = RecordingLink(); val e = route(l); e.start(start); tick(e, start, 0.0); tick(e, start, 2.0, available = false)
        assertFalse(e.active); assertEquals("c0,0", l.frame)
    }
    @Test fun bumperZeroIsCollisionId() {
        val l = RecordingLink(); val e = route(l); e.start(start)
        OpenBotProtocol.applyLine(l.telemetry, "b0", 0.0); tick(e, start, 0.0)
        assertFalse(e.active); assertEquals("c0,0", l.frame)
    }
    @Test fun sonarAndWheelReadingsCannotBlockOrDriveRoute() {
        val l = RecordingLink(); val e = route(l); l.telemetry.sonarCm = 1.0; l.telemetry.rpmLeft = 99999.0
        e.start(start); tick(e, start, 0.0); tick(e, start, 2.0)
        assertEquals("c160,160", l.frame)
        tick(e, start, 3.0); assertEquals(1, e.targetIndex) // no arrival from fake wheels
    }
    @Test fun farFromStartRefusesAndStops() {
        val l = RecordingLink(); val e = route(l)
        assertThrows(IllegalArgumentException::class.java) { e.start(Planar(1.0, 0.0, 0.0)) }
        assertFalse(e.active); assertEquals("c0,0", l.frame)
    }
    @Test fun nonFinitePoseStops() {
        val l = RecordingLink(); val e = route(l); e.start(start); tick(e, start.copy(x = Double.NaN), 0.0)
        assertFalse(e.active)
    }
    @Test fun invalidClockStops() {
        val l = RecordingLink(); val e = route(l); e.start(start); tick(e, start, Double.NaN)
        assertFalse(e.active)
    }
    @Test fun zeroPwmDoesNotMove() {
        val l = RecordingLink(); val e = WaypointExecutor(listOf(NavPoint("s", start), NavPoint("g", Planar(2.0,0.0,0.0))), l, PwmSettings(0,0,0))
        e.start(start); tick(e, start, 0.0); tick(e, start, 2.0); assertEquals("c0,0", l.frame)
    }
    @Test fun corruptTargetIsRejected() {
        val l = RecordingLink(); val e = WaypointExecutor(listOf(NavPoint("s", start), NavPoint("bad", start.copy(yawRad=Double.NaN))), l, settings)
        assertThrows(IllegalArgumentException::class.java) { e.start(start) }
        assertFalse(e.active)
    }
    @Test fun shortPulseUsesDirectionalPwmAndStopsAtOneSecond() {
        val l = RecordingLink(); val p = PwmPulseTester(l)
        assertTrue(p.start(PwmTestAction.LEFT, settings, 0.0)); assertEquals("c-140,140", l.frame)
        p.tick(.999); assertEquals("c-140,140", l.frame); p.tick(1.0); assertEquals("c0,0", l.frame)
        assertTrue(p.start(PwmTestAction.RIGHT, settings, 2.0)); assertEquals("c180,-180", l.frame)
        p.stop(); p.tick(2.5); assertEquals("c0,0", l.frame)
    }
    @Test fun pulseStopsOnDisconnection() {
        val l = RecordingLink(); val p = PwmPulseTester(l); p.start(PwmTestAction.FORWARD, settings, 0.0)
        l.telemetry.connected = false; p.tick(.2); assertFalse(p.active); assertEquals("c0,0", l.frame)
        assertFalse(p.start(PwmTestAction.LEFT, settings, .3))
    }
    @Test fun pulseStopsOnCollision() {
        val l = RecordingLink(); val p = PwmPulseTester(l); p.start(PwmTestAction.FORWARD, settings, 0.0)
        l.telemetry.bumper = "0"; p.tick(.2); assertFalse(p.active); assertEquals("c0,0", l.frame)
    }
    @Test fun pwmRangeValidation() {
        assertTrue(PwmSettings().valid); assertTrue(PwmSettings(0,255,160).valid)
        assertFalse(PwmSettings(-1,160,160).valid); assertFalse(PwmSettings(160,256,160).valid)
    }
    @Test fun protocolPreservesSignedPwmAndRounding() {
        assertEquals("c160,-160\n", OpenBotProtocol.ctrlCmd(160.0/255, -160.0/255).toString(Charsets.US_ASCII))
        assertEquals(1, OpenBotProtocol.speedToPwm(.5/255)); assertEquals(-1, OpenBotProtocol.speedToPwm(-.5/255))
        assertEquals("c255,-255\n", OpenBotProtocol.ctrlCmd(2.0,-2.0).toString(Charsets.US_ASCII))
        assertEquals("c0,0\n", OpenBotProtocol.ctrlCmd(Double.NaN,1.0).toString(Charsets.US_ASCII))
    }
    @Test fun telemetryReassemblesSplitLinesAndIgnoresFakeSonar() {
        val t = Telemetry(); val s = TelemetryStream()
        s.receive("v12.".toByteArray(),t,1.0); assertNull(t.voltage)
        s.receive("4\nw900,".toByteArray(),t,2.0); assertEquals(12.4,t.voltage!!,1e-9)
        s.receive("901\ns1\nfrobot\n".toByteArray(),t,3.0)
        assertEquals(900.0,t.rpmLeft,0.0); assertEquals(901.0,t.rpmRight,0.0); assertNull(t.sonarCm)
        assertEquals("robot",t.features)
    }
    @Test fun jsonPreservesSequenceOrientationAndPhysicalWidth() {
        val r = StoredRoute("走廊", "entrance", listOf(
            RouteNode(TYPE_START, .2, .4, .3, .6, "起点"),
            RouteNode(TYPE_INTERMEDIATE, 2.0, .0, 0.0, 1.2, "节点1"),
            RouteNode(TYPE_DESTINATION, .0, .0, -2.0, -1.2, "节点2")), .173f)
        val restored = RouteCodec.decode(RouteCodec.encode(listOf(r))).single()
        assertEquals(r,restored); assertEquals(4.0,restored.pathLengthM(),1e-9)
        assertEquals(.2,restored.navPoints()[0].pose.x,1e-9)
        assertEquals(2.2,restored.navPoints()[1].pose.x,1e-9)
        assertEquals(1.7,restored.navPoints()[2].pose.y,1e-9)
        assertEquals(-1.2,restored.navPoints()[2].pose.yawRad,1e-9)
    }
    @Test fun legacyRouteGetsSegmentHeadingAndOriginalPrintWidth() {
        val json = """{"destination":{"old":{"beacon_name":"pi","nodes":{"index":[{"type":"start"},{"x_offset":1},{"z_offset":-1}]}}}}"""
        val r = RouteCodec.decode(json).single()
        assertEquals(.0762f,r.anchorWidthM,1e-6f)
        assertEquals(0.0,r.navPoints()[0].pose.yawRad,1e-9)
        assertEquals(Math.PI/2,r.navPoints()[1].pose.yawRad,1e-9)
        assertEquals(Math.PI/2,r.navPoints()[2].pose.yawRad,1e-9)
    }
    @Test fun headingWrapTakesShortTurn() {
        assertEquals(Math.toRadians(2.0),Planar.wrapRad(Math.toRadians(-358.0)),1e-9)
        assertEquals(-Math.toRadians(2.0),Planar.wrapRad(Math.toRadians(358.0)),1e-9)
    }
}
