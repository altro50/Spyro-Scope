using OpenGL;
using SDL2;
using System;
using System.Collections;
using System.Diagnostics;

namespace SpyroScope {
	class Renderer {
		SDL.Window* window;
		SDL.SDL_GLContext context;

		static bool useSync;

		public struct Color {
			public uint8 r,g,b;
			public this(uint8 r, uint8 g, uint8 b) {
				this.r = r;
				this.g = g;
				this.b = b;
			}
		}

		public struct Color4 {
			public uint8 r,g,b,a;
			public this(uint8 r, uint8 g, uint8 b, uint8 a) {
				this.r = r;
				this.g = g;
				this.b = b;
				this.a = a;
			}
		}

		const uint maxGenericBufferLength = 0x6000;
		uint vertexArrayObject;
		Buffer<Vector> positions;
		Buffer<Vector> normals;
		Buffer<Color> colors;
		Buffer<(float,float)> uvs;
		DrawQueue[maxGenericBufferLength] drawQueue;
		DrawQueue* startDrawQueue, lastDrawQueue;
		
		uint32 vertexCount, vertexOffset;

		uint vertexShader;
		uint fragmentShader;
		uint program;

		// Shader Inputs
		public static uint positionAttributeIndex;
		public static uint normalAttributeIndex;
		public static uint colorAttributeIndex;
		public static uint uvAttributeIndex;

		public static uint instanceMatrixAttributeIndex;
		public static uint instanceTintAttributeIndex;

		// Shader Uniforms
		public Matrix4 model = .Identity;
		public int uniformViewMatrixIndex; // Camera Inverse Transform
		public Matrix4 view = .Identity;
		public Vector viewPosition = .Zero;
		public Matrix viewBasis = .Identity;
		public int uniformProjectionMatrixIndex; // Camera Perspective
		public Matrix4 projection = .Identity;

		public Vector tint = .(1,1,1);
		public int uniformZdepthOffsetIndex; // Z-depth Offset (mainly for pushing the wireframe forward to avoid Z-fighting)

		public uint textureDefaultWhite;

		public struct Buffer<T> {
			public uint obj;
			public T* map;
			public readonly int bufferLength;

			public this(int bufferLength) {
				obj = 0;

				// Generate
				GL.glGenBuffers(1, &obj);
				// Bind
				GL.glBindBuffer(GL.GL_ARRAY_BUFFER, obj);

				// Calculate Buffer size
				let item_size = sizeof(T);
				let buffer_size = item_size * bufferLength;

				let access = GL.GL_MAP_WRITE_BIT | GL.GL_MAP_PERSISTENT_BIT;

				GL.glBufferStorage(GL.GL_ARRAY_BUFFER, buffer_size, null, access);
				map = (T*)GL.glMapBufferRange(GL.GL_ARRAY_BUFFER, 0, buffer_size, access);

				for (int i < bufferLength) {
					*(map + i) = default;
				}

				this.bufferLength = bufferLength;
			}

			//[Optimize]
			public void Set(uint32 index, T value) mut {
				if (index >= bufferLength) {
					return;
				}

				*(map + index) = value;
			}

			public void Dispose() mut {
				GL.glBindBuffer(GL.GL_ARRAY_BUFFER, obj);
				GL.glUnmapBuffer(GL.GL_ARRAY_BUFFER);
				GL.glDeleteBuffers(1, &obj);
			}
		}

		struct DrawQueue {
			public uint16 type;
			public uint16 count;
			public uint8 texture;

			public this(uint16 drawType, uint16 vertexCount, uint8 textureObject) {
				type = drawType;
				count = vertexCount;
				texture = textureObject;
			}
		}

		public this(SDL.Window* window) {
			drawQueue[0].type = 0;
			drawQueue[0].count = 0;
			startDrawQueue = lastDrawQueue = &drawQueue[0];

			// Initialize OpenGL
			SDL.GL_SetAttribute(.GL_CONTEXT_FLAGS, (.)SDL.SDL_GLContextFlags.GL_CONTEXT_DEBUG_FLAG);

			context = SDL.GL_CreateContext(window);
			GL.Init(=> SdlGetProcAddress);

			int32 majorVersion = ?;
			int32 minorVersion = ?;
			GL.glGetIntegerv(GL.GL_MAJOR_VERSION, (.)&majorVersion);
			GL.glGetIntegerv(GL.GL_MINOR_VERSION, (.)&minorVersion);
			Console.WriteLine("OpenGL {}.{}", majorVersion, minorVersion);

			if (majorVersion > 3 || majorVersion == 3 && minorVersion > 1) {
				useSync = true;
			}

			Clear();
			SDL.GL_SwapWindow(window);

			// Compile shaders during run-time
			vertexShader = CompileShader("shaders/vertex.glsl", GL.GL_VERTEX_SHADER);
			fragmentShader = CompileShader("shaders/fragment.glsl", GL.GL_FRAGMENT_SHADER);

			// Link and use the shader program
			program = LinkProgram(vertexShader, fragmentShader);
			GL.glUseProgram(program);

			// Create Buffers/Arrays

			vertexArrayObject = 0;
			GL.glGenVertexArrays(1, &vertexArrayObject);
			GL.glBindVertexArray(vertexArrayObject);

			// Position Buffer
			positions = .(maxGenericBufferLength);
			positionAttributeIndex = FindProgramAttribute(program, "vertexPosition");
			GL.glVertexAttribPointer(positionAttributeIndex, 3, GL.GL_FLOAT, GL.GL_FALSE, 0, null);
			GL.glEnableVertexAttribArray(positionAttributeIndex);

			// Normals Buffer
			normals = .(maxGenericBufferLength);
			normalAttributeIndex = FindProgramAttribute(program, "vertexNormal");
			GL.glVertexAttribPointer(normalAttributeIndex, 3, GL.GL_FLOAT, GL.GL_FALSE, 0, null);
			GL.glEnableVertexAttribArray(normalAttributeIndex);

			// Color Buffer
			colors = .(maxGenericBufferLength);
			colorAttributeIndex = FindProgramAttribute(program, "vertexColor");
			GL.glVertexAttribIPointer(colorAttributeIndex, 3, GL.GL_UNSIGNED_BYTE, 0, null);
			GL.glEnableVertexAttribArray(colorAttributeIndex);

			// UV Buffer
			uvs = .(maxGenericBufferLength);
			uvAttributeIndex = FindProgramAttribute(program, "vertexTextureMapping");
			GL.glVertexAttribPointer(uvAttributeIndex, 2, GL.GL_FLOAT, GL.GL_FALSE, 0, null);
			GL.glEnableVertexAttribArray(uvAttributeIndex);

			uint tempBufferID = ?;
			GL.glGenBuffers(1, &tempBufferID);
			GL.glBindBuffer(GL.GL_ARRAY_BUFFER, tempBufferID);
			GL.glBufferData(GL.GL_ARRAY_BUFFER, sizeof(Matrix4), &model, GL.GL_STATIC_DRAW);
			
			instanceMatrixAttributeIndex = FindProgramAttribute(program, "instanceModel");

			GL.glVertexAttribPointer(instanceMatrixAttributeIndex+0, 4, GL.GL_FLOAT, GL.GL_FALSE, sizeof(Matrix4), (void*)(4*0));
			GL.glVertexAttribPointer(instanceMatrixAttributeIndex+1, 4, GL.GL_FLOAT, GL.GL_FALSE, sizeof(Matrix4), (void*)(4*4));
			GL.glVertexAttribPointer(instanceMatrixAttributeIndex+2, 4, GL.GL_FLOAT, GL.GL_FALSE, sizeof(Matrix4), (void*)(4*8));
			GL.glVertexAttribPointer(instanceMatrixAttributeIndex+3, 4, GL.GL_FLOAT, GL.GL_FALSE, sizeof(Matrix4), (void*)(4*12));

			GL.glEnableVertexAttribArray(instanceMatrixAttributeIndex+0);
			GL.glEnableVertexAttribArray(instanceMatrixAttributeIndex+1);
			GL.glEnableVertexAttribArray(instanceMatrixAttributeIndex+2);
			GL.glEnableVertexAttribArray(instanceMatrixAttributeIndex+3);

			GL.glVertexAttribDivisor(instanceMatrixAttributeIndex+0, 1);
			GL.glVertexAttribDivisor(instanceMatrixAttributeIndex+1, 1);
			GL.glVertexAttribDivisor(instanceMatrixAttributeIndex+2, 1);
			GL.glVertexAttribDivisor(instanceMatrixAttributeIndex+3, 1);

			GL.glGenBuffers(1, &tempBufferID);
			GL.glBindBuffer(GL.GL_ARRAY_BUFFER, tempBufferID);
			GL.glBufferData(GL.GL_ARRAY_BUFFER, sizeof(Vector), &tint, GL.GL_STATIC_DRAW);

			instanceTintAttributeIndex = FindProgramAttribute(program, "instanceTint");
			GL.glVertexAttribPointer(instanceTintAttributeIndex, 3, GL.GL_FLOAT, GL.GL_FALSE, 0, null);
			GL.glEnableVertexAttribArray(instanceTintAttributeIndex);
			GL.glVertexAttribDivisor(instanceTintAttributeIndex, 1);

			// Get Uniforms
			uniformViewMatrixIndex = FindProgramUniform(program, "view");
			uniformProjectionMatrixIndex = FindProgramUniform(program, "projection");
			uniformZdepthOffsetIndex = FindProgramUniform(program, "zdepthOffset");

			// Create Default Texture

			var tempTexData = Color4[1](.(255,255,255,255));
			GL.glGenTextures(1, &textureDefaultWhite);
			GL.glBindTexture(GL.GL_TEXTURE_2D, textureDefaultWhite);
			GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, 1, 1, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, &tempTexData);

			this.window = window;

			GL.glEnable(GL.GL_FRAMEBUFFER_SRGB); 
			GL.glEnable(GL.GL_DEPTH_TEST);
			GL.glEnable(GL.GL_BLEND);
			GL.glBlendFunc(GL.GL_SRC_ALPHA, GL.GL_ONE_MINUS_SRC_ALPHA);

			GL.glEnable(GL.GL_CULL_FACE);
			GL.glCullFace(GL.GL_BACK);
			GL.glFrontFace(GL.GL_CW);

			CheckForErrors();

			PrimitiveShape.Init();
		}

		public ~this() {
			GL.glDeleteVertexArrays(1, &vertexArrayObject);
			GL.glDeleteShader(vertexShader);
			GL.glDeleteShader(fragmentShader);
			GL.glDeleteProgram(program);

			positions.Dispose();
			normals.Dispose();
			colors.Dispose();
		}

		uint CompileShader(String sourcePath, uint shaderType) {
			let shader = GL.glCreateShader(shaderType);

			String source = scope .();
			System.IO.File.ReadAllText(sourcePath, source, true);
			char8* sourceData = source.Ptr;

			GL.glShaderSource(shader, 1, &sourceData, null);
			GL.glCompileShader(shader);

			int status = GL.GL_FALSE;
			GL.glGetShaderiv(shader, GL.GL_COMPILE_STATUS, &status);
			Debug.Assert(status == GL.GL_TRUE, "Shader compilation failed");

			return shader;
		}

		uint LinkProgram(uint vertex, uint fragment) {
			let program = GL.glCreateProgram();

			GL.glAttachShader(program, vertex);
			GL.glAttachShader(program, fragment);

			GL.glLinkProgram(program);

			int status = GL.GL_FALSE;
			GL.glGetProgramiv(program, GL.GL_LINK_STATUS, &status);
			Debug.Assert(status == GL.GL_TRUE, "Program linking failed");

			return program;
		}

		uint FindProgramAttribute(uint program, String attribute) {
			let index = GL.glGetAttribLocation(program, attribute.Ptr);

			Debug.Assert(index >= 0, "Attribute not found");

			return (uint)index;
		}

		int FindProgramUniform(uint program, String attribute) {
			let index = GL.glGetUniformLocation(program, attribute.Ptr);

			Debug.Assert(index >= 0, "Uniform not found");

			return index;
		}

		public void PushPoint(Vector position, Vector normal, Color color, (float,float) uv) {
			positions.Set(vertexCount, position);
			normals.Set(vertexCount, normal);
			colors.Set(vertexCount, color);
			uvs.Set(vertexCount, uv);

			vertexCount++;
		}

		public void DrawLine(Vector p0, Vector p1,
			Color c0, Color c1) {
			if (vertexCount + 2 > maxGenericBufferLength) {
				Draw();
			}
				
			let normal = Vector(0,0,1);

			PushPoint(p0, normal, c0, (0,0));
			PushPoint(p1, normal, c1, (0,0));

			if (lastDrawQueue.type == GL.GL_LINES) {
				lastDrawQueue.count += 2;
			} else {
				lastDrawQueue++;
				lastDrawQueue.type = GL.GL_LINES;
				lastDrawQueue.count = 2;
				lastDrawQueue.texture = (uint8)textureDefaultWhite;
			}
		}

		public void DrawTriangle(Vector p0, Vector p1, Vector p2,
			Color c0, Color c1, Color c2,
			(float,float) uv0, (float,float) uv1, (float,float) uv2, uint textureObject) {
			if (vertexCount + 3 > maxGenericBufferLength) {
				Draw();
			}

			let normal = Vector.Cross(p2 - p0, p1 - p0);

			PushPoint(p0, normal, c0, uv0);
			PushPoint(p1, normal, c1, uv1);
			PushPoint(p2, normal, c2, uv2);

			if (lastDrawQueue.type == GL.GL_TRIANGLES && lastDrawQueue.texture == textureObject) {
				lastDrawQueue.count += 3;
			} else {
				lastDrawQueue++;
				lastDrawQueue.type = GL.GL_TRIANGLES;
				lastDrawQueue.count = 3;
				lastDrawQueue.texture = (.)textureObject;
			}
		}

		public void DrawTriangle(Vector p0, Vector p1, Vector p2,
			Color c0, Color c1, Color c2) {
			DrawTriangle(p0, p1, p2, c0, c1, c2, (0,0), (0,0), (0,0), textureDefaultWhite);
		}

		public void SetModel(Vector position, Matrix basis) {
			model = Matrix4.Translation(position) * basis;
		}

		public void SetView(Vector position, Matrix basis) {
			viewPosition = position;
			viewBasis = basis;
			view = basis.Transpose() * Matrix4.Translation(-position);
			GL.glUniformMatrix4fv(uniformViewMatrixIndex, 1, GL.GL_FALSE, (float*)&view);
		}

		public void SetProjection(Matrix4 projection) {
			this.projection = projection;
			GL.glUniformMatrix4fv(uniformProjectionMatrixIndex, 1, GL.GL_FALSE, (float*)&this.projection);
		}

		public void SetTint(Color tint) {
			this.tint = .((float)tint.r / 255, (float)tint.g / 255, (float)tint.b / 255);
			//GL.glUniform3fv(uniformTintIndex, 1, &this.tint[0]);
		}

		public void BeginWireframe() {
			GL.glPolygonMode(GL.GL_FRONT_AND_BACK, GL.GL_LINE);
			GL.glUniform1f(uniformZdepthOffsetIndex, 0.5f); // Push the lines a little forward
		}

		public void BeginSolid() {
			GL.glPolygonMode(GL.GL_FRONT_AND_BACK, GL.GL_FILL);
			GL.glUniform1f(uniformZdepthOffsetIndex, 0); // Reset depth offset
		}

		public void Draw() {
			GL.glBindVertexArray(vertexArrayObject);

			startDrawQueue++;
			while (startDrawQueue <= lastDrawQueue) {
				GL.glBindTexture(GL.GL_TEXTURE_2D, startDrawQueue.texture);
				GL.glDrawArrays(startDrawQueue.type, vertexOffset, startDrawQueue.count);
				vertexOffset += startDrawQueue.count;
				startDrawQueue++;
			}
			
			startDrawQueue.count = startDrawQueue.type = 0;
			lastDrawQueue = startDrawQueue;
		}

		public void Sync() {
			// Wait for GPU
			if (useSync) {
				var sync = GL.glFenceSync(GL.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);

				while (GL.glClientWaitSync(sync, GL.GL_SYNC_FLUSH_COMMANDS_BIT, 0) == GL.GL_TIMEOUT_EXPIRED) {
					// Insert something here to do while waiting for draw to finish
					SDL.Delay(0);
				}
				GL.glDeleteSync(sync);
			} else {
				GL.glFinish();
			}
		}

		public void Display() {
			SDL.GL_SwapWindow(window);
		}

		public void Clear() {
			GL.glClearColor(0,0,0,1);
			GL.glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT);
			startDrawQueue = lastDrawQueue = &drawQueue[0];
			vertexCount = vertexOffset = 0;
		}

		public static void CheckForErrors() {
			char8[] buffer = scope .[1024];
			uint severity = 0;
			uint source = 0;
			int messageSize = 0;
			uint mType = 0;
			uint id = 0;

			bool error = false;

			while (GL.glGetDebugMessageLog(1, 1024, &source, &mType, &id, &severity, &messageSize, &buffer[0]) > 0) {
				if (severity == GL.GL_DEBUG_SEVERITY_HIGH) {
					error = true;
				}

				String string = scope .(buffer, 0, 1024);
				Debug.WriteLine(scope String() .. AppendF("OpenGL: {}", string));
			}

			if (error) {
				Debug.FatalError("Fatal OpenGL Error");
			}
		}
	}
}
