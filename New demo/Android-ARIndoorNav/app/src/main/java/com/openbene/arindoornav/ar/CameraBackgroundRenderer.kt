package com.openbene.arindoornav.ar

import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import com.google.ar.core.Frame
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Draws the ARCore camera feed as a full screen quad, the standard approach from
 * the ARCore samples: ARCore writes the camera image into an external OES
 * texture and [Frame.transformDisplayUvCoords] gives the UVs that match the
 * current display rotation.
 */
class CameraBackgroundRenderer {

    private var program = 0
    private var textureId = -1
    private var positionAttrib = 0
    private var texCoordAttrib = 0
    private var textureUniform = 0

    private val quadVertices = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
    private val quadTexCoords = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
    private val quadTexCoordsTransformed = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
    private var uvReady = false
    private val projectionMatrix = FloatArray(16)

    val cameraTextureId: Int get() = textureId

    init {
        quadVertices.put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)).position(0)
        quadTexCoords.put(floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f)).position(0)
    }

    fun createOnGlThread(context: Context) {
        uvReady = false
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)
        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        texCoordAttrib = GLES20.glGetAttribLocation(program, "a_TexCoord")
        textureUniform = GLES20.glGetUniformLocation(program, "u_Texture")

        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST,
        )
    }

    fun draw(frame: Frame) {
        if (program == 0) return
        if (!uvReady || frame.hasDisplayGeometryChanged()) {
            frame.transformDisplayUvCoords(quadTexCoords, quadTexCoordsTransformed)
            uvReady = true
        }

        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glDisable(GLES20.GL_CULL_FACE)

        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glUniform1i(textureUniform, 0)

        GLES20.glVertexAttribPointer(
            positionAttrib, 2, GLES20.GL_FLOAT, false, 0, quadVertices.position(0),
        )
        GLES20.glVertexAttribPointer(
            texCoordAttrib, 2, GLES20.GL_FLOAT, false, 0, quadTexCoordsTransformed.position(0),
        )
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glEnableVertexAttribArray(texCoordAttrib)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisableVertexAttribArray(texCoordAttrib)
        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    /** ARCore camera projection, used to place 3D overlays in the same view. */
    fun projectionMatrix(frame: Frame): FloatArray {
        frame.camera.getProjectionMatrix(projectionMatrix, 0, 0.05f, 30.0f)
        return projectionMatrix
    }

    private fun loadShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        return shader
    }

    companion object {
        private const val VERTEX_SHADER = "attribute vec4 a_Position;\n" +
            "attribute vec2 a_TexCoord;\n" +
            "varying vec2 v_TexCoord;\n" +
            "void main() {\n" +
            "  v_TexCoord = a_TexCoord;\n" +
            "  gl_Position = a_Position;\n" +
            "}\n"

        private const val FRAGMENT_SHADER = "#extension GL_OES_EGL_image_external : require\n" +
            "precision mediump float;\n" +
            "varying vec2 v_TexCoord;\n" +
            "uniform samplerExternalOES u_Texture;\n" +
            "void main() {\n" +
            "  gl_FragColor = texture2D(u_Texture, v_TexCoord);\n" +
            "}\n"
    }
}
