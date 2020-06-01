namespace SpyroScope {
	static struct PrimitiveShape {
		public static StaticMesh cube;

		public static void Init() {
			GenerateCube();
		}

		public static void GenerateCube() {
			let vertices = new Vector[24](
				.(0.5f,0.5f,0.5f),
				.(0.5f,0.5f,0.5f),
				.(0.5f,0.5f,0.5f),
				.(-0.5f,0.5f,0.5f),
				.(-0.5f,0.5f,0.5f),
				.(-0.5f,0.5f,0.5f),
				.(0.5f,-0.5f,0.5f),
				.(0.5f,-0.5f,0.5f),//
				.(0.5f,-0.5f,0.5f),
				.(-0.5f,-0.5f,0.5f),
				.(-0.5f,-0.5f,0.5f),//
				.(-0.5f,-0.5f,0.5f),

				.(0.5f,0.5f,-0.5f),
				.(0.5f,0.5f,-0.5f),
				.(0.5f,0.5f,-0.5f),
				.(-0.5f,0.5f,-0.5f),
				.(-0.5f,0.5f,-0.5f),
				.(-0.5f,0.5f,-0.5f),
				.(0.5f,-0.5f,-0.5f),
				.(0.5f,-0.5f,-0.5f),//
				.(0.5f,-0.5f,-0.5f),
				.(-0.5f,-0.5f,-0.5f),
				.(-0.5f,-0.5f,-0.5f),//
				.(-0.5f,-0.5f,-0.5f)
			);

			let normals = new Vector[24](
				.(1.0f,0.0f,0.0f),
				.(0.0f,1.0f,0.0f),
				.(0.0f,0.0f,1.0f),
				.(-1.0f,0.0f,0.0f),
				.(0.0f,1.0f,0.0f),
				.(0.0f,0.0f,1.0f),
				.(1.0f,0.0f,0.0f),
				.(0.0f,-1.0f,0.0f), //7
				.(0.0f,0.0f,1.0f),
				.(-1.0f,0.0f,0.0f),
				.(0.0f,-1.0f,0.0f),
				.(0.0f,0.0f,1.0f),
				
				.(1.0f,0.0f,0.0f), //12
				.(0.0f,1.0f,0.0f),
				.(0.0f,0.0f,-1.0f),
				.(-1.0f,0.0f,0.0f),
				.(0.0f,1.0f,0.0f),
				.(0.0f,0.0f,-1.0f),
				.(1.0f,0.0f,0.0f),
				.(0.0f,-1.0f,0.0f), //19
				.(0.0f,0.0f,-1.0f),
				.(-1.0f,0.0f,0.0f),
				.(0.0f,-1.0f,0.0f),
				.(0.0f,0.0f,-1.0f) //23
			);

			let colors = new Renderer.Color[24];
			for	(int i < 24) {
				colors[i] = .(255,255,255);
			}

			let indices = new uint32[36](
				0, 12, 6, 6, 12, 18,
				1, 4, 13, 13, 4, 16,
				2, 8, 5, 5, 8, 11,
				3, 9, 15, 15, 9, 21,
				7, 19, 10, 10, 19, 22,
				14, 17, 20, 20, 17, 23
			);

			cube = new .(vertices, normals, colors, indices);
		}
	}
}
