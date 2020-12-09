using OpenGL;
using System.Collections;

namespace SpyroScope {
	struct TextureScroller {
		Emulator.Address address;
		public uint8 textureIndex;
		
		public TerrainRegion[] visualMeshes;
		public Dictionary<uint8, List<int>> affectedTriangles = new .();
		public Dictionary<uint8, List<int>> affectedTransparentTriangles = new .();
		
		public struct KeyframeData {
			public uint8 a, nextFrame, b, verticalOffset;
		}

		public uint8 CurrentKeyframe {
			get {
				uint8 currentKeyframe = ?;
				Emulator.ReadFromRAM(address + 2, &currentKeyframe, 1);
				return currentKeyframe;
			}
		}

		public this(Emulator.Address address, TerrainRegion[] visualMeshes) {
			this = ?;

			this.address = address;
			this.visualMeshes = visualMeshes;

			Emulator.ReadFromRAM(address + 4, &textureIndex, 1);
		}

		public void Dispose() {
			for (var pair in affectedTriangles) {
				delete pair.value;
			}
			delete affectedTriangles;

			for (var pair in affectedTransparentTriangles) {
				delete pair.value;
			}
			delete affectedTransparentTriangles;
		}

		public void Reload() mut {
			for (let pair in affectedTriangles) {
				delete pair.value;
			}
			affectedTriangles.Clear();
			for (let pair in affectedTransparentTriangles) {
				delete pair.value;
			}
			affectedTransparentTriangles.Clear();

			if (address.IsNull)
				return;

			for (let regionIndex < visualMeshes.Count) {
				let terrainRegion = visualMeshes[regionIndex];

				for (var triangleIndex = 0; triangleIndex < terrainRegion.nearTri2TextureIndices.Count; triangleIndex++) {
					if (terrainRegion.nearTri2TextureIndices[triangleIndex] == textureIndex) {
						if (!affectedTriangles.ContainsKey((.)regionIndex)) {
							affectedTriangles[(.)regionIndex] = new .();
						}
						affectedTriangles[(.)regionIndex].Add(triangleIndex);
					}
				}
				
				for (var triangleIndex = 0; triangleIndex < terrainRegion.nearTri2TransparentTextureIndices.Count; triangleIndex++) {
					if (terrainRegion.nearTri2TransparentTextureIndices[triangleIndex] == textureIndex) {
						if (!affectedTransparentTriangles.ContainsKey((.)regionIndex)) {
							affectedTransparentTriangles[(.)regionIndex] = new .();
						}
						affectedTransparentTriangles[(.)regionIndex].Add(triangleIndex);
					}
				}
			}
		}

		public void GetUsedTextures() {
			if (!Terrain.usedTextureIndices.Contains(textureIndex)) {
				Terrain.usedTextureIndices.Add(textureIndex);
			}
		}

		public void Decode() {
			let quadCount = Emulator.installment == .SpyroTheDragon ? 21 : 6;
			for (let i < quadCount) {
				let quad = (TextureQuad*)&Terrain.textureInfos[textureIndex * quadCount + i];

				let verticalQuad = (quad.texturePage & 0x80 > 0) ? 3 : 2;
				quad.leftSkew = 0;
				quad.rightSkew = (uint8)(verticalQuad * 0x20 - 1);
				quad.Decode();
			}
		}

		// Derived from Spyro the Dragon [8002b578]
		// Derived from Spyro: Ripto's Rage [8002270c]
		public void Update() {
			uint8 verticalPosition = ?;
			Emulator.ReadFromRAM(address + 6, &verticalPosition, 1);

			let quadVerticalPosition = verticalPosition >> 2;

			if (Emulator.installment == .SpyroTheDragon) {
				let textureLOD = (TextureQuad*)&Terrain.textureInfos[(int)textureIndex * 21];

				textureLOD[0].leftSkew = textureLOD[0].rightSkew = quadVerticalPosition;
				for (uint8 i < 4) {
					textureLOD[1 + i].leftSkew = textureLOD[1 + i].rightSkew = ((verticalPosition >> 1) + (i / 2 * 0x20)) & 0x3f;
				}
				for (uint8 i < 16) {
					textureLOD[5 + i].leftSkew = textureLOD[5 + i].rightSkew = (verticalPosition + (i / 4 * 0x20)) & 0x3f;
				}
			} else {
				let textureLOD = (TextureLOD*)&Terrain.textureInfos[(int)textureIndex * 6];
				let farQuad = &textureLOD.farQuad;
				let nearQuad = &textureLOD.nearQuad;
				farQuad.leftSkew = nearQuad.leftSkew = quadVerticalPosition;
				farQuad.rightSkew = nearQuad.rightSkew = quadVerticalPosition + 0x1f;
	
				var doubleQuadVerticalPosition = verticalPosition >> 1;
	
				let topLeftQuad = &textureLOD.topLeftQuad;
				let topRightQuad = &textureLOD.topRightQuad;
				topLeftQuad.leftSkew = topRightQuad.leftSkew = doubleQuadVerticalPosition;
				topLeftQuad.rightSkew = topRightQuad.rightSkew = doubleQuadVerticalPosition + 0x1f;
	
				doubleQuadVerticalPosition = (doubleQuadVerticalPosition + 0x20) & 0x3f;
	
				let bottomLeftQuad = &textureLOD.bottomLeftQuad;
				let bottomRightQuad = &textureLOD.bottomRightQuad;
				bottomLeftQuad.leftSkew = bottomRightQuad.leftSkew = doubleQuadVerticalPosition;
				bottomLeftQuad.rightSkew = bottomRightQuad.rightSkew = doubleQuadVerticalPosition + 0x1f;
			}
		}

		public KeyframeData GetKeyframeData(uint8 keyframeIndex) {
			KeyframeData keyframeData = ?;
			Emulator.ReadFromRAM(address + 8 + ((uint32)keyframeIndex) * 4, &keyframeData, 4);
			return keyframeData;
		}

		public void UpdateUVs(bool transparent) {
			let quadCount = Emulator.installment == .SpyroTheDragon ? 21 : 6;
			TextureQuad* quad = &Terrain.textureInfos[textureIndex * quadCount];
			if (Emulator.installment != .SpyroTheDragon) {
				quad++;
			}

			float[4 * 5][2] triangleUV = ?;
			for (let qi < 5) {
				let partialUV = quad.GetVramPartialUV();

				let offset = qi * 4;
				triangleUV[0 + offset] = .(partialUV.left, partialUV.rightY);
				triangleUV[1 + offset] = .(partialUV.right, partialUV.rightY);
				triangleUV[2 + offset] = .(partialUV.right, partialUV.leftY);
				triangleUV[3 + offset] = .(partialUV.left, partialUV.leftY);

				quad++;
			}

			let affectedTriangles = transparent ? affectedTransparentTriangles : affectedTriangles;
			for (let affectedRegionTriPair in affectedTriangles) {
				let terrainRegion = visualMeshes[affectedRegionTriPair.key];
				let faceIndices = transparent ? terrainRegion.nearFaceTransparentIndices : terrainRegion.nearFaceIndices;
				let regionMesh = transparent ? terrainRegion.nearMeshTransparent : terrainRegion.nearMesh;
				let regionMeshSubdivided = transparent ? terrainRegion.nearMeshTransparentSubdivided : terrainRegion.nearMeshSubdivided;

				for (var i < affectedRegionTriPair.value.Count) {
					let triangleIndex = affectedRegionTriPair.value[i];
					let vertexIndex = triangleIndex * 3;
					let subdividedVertexIndex = triangleIndex * 3 * 4;

					let nearFaceIndex = faceIndices[triangleIndex];
					TerrainRegion.NearFace regionFace = terrainRegion.nearFaces[nearFaceIndex];
					let textureRotation = regionFace.renderInfo.rotation;

					if (regionFace.isTriangle) {
						float[4][2] rotatedTriangleUV = .((?),
							triangleUV[(0 - textureRotation) & 3],
							triangleUV[(2 - textureRotation) & 3],
							triangleUV[(3 - textureRotation) & 3]
						);

						int8[2] indexSwap = regionFace.flipped ? .(1,3) : .(3,1);

						regionMesh.uvs[0 + vertexIndex] = rotatedTriangleUV[indexSwap[0]];
						regionMesh.uvs[1 + vertexIndex] = rotatedTriangleUV[2];
						regionMesh.uvs[2 + vertexIndex] = rotatedTriangleUV[indexSwap[1]];

						for (let ti < 3) {
							let offset = (1 + ti) * 4;

							rotatedTriangleUV = .((?),
								triangleUV[((3 - (textureRotation)) & 3) + offset],
								triangleUV[((2 - (textureRotation)) & 3) + offset],
								triangleUV[((0 - (textureRotation)) & 3) + offset]
							);

							regionMeshSubdivided.uvs[0 + (ti * 3) + subdividedVertexIndex] = rotatedTriangleUV[indexSwap[1]];
							regionMeshSubdivided.uvs[1 + (ti * 3) + subdividedVertexIndex] = rotatedTriangleUV[2];
							regionMeshSubdivided.uvs[2 + (ti * 3) + subdividedVertexIndex] = rotatedTriangleUV[indexSwap[0]];
						}

						rotatedTriangleUV = .((?),
							triangleUV[((0 - (textureRotation)) & 3) + 4],
							triangleUV[((2 - (textureRotation)) & 3) + 4],
							triangleUV[((1 - (textureRotation)) & 3) + 4],
						);

						regionMeshSubdivided.uvs[0 + (3 * 3) + subdividedVertexIndex] = rotatedTriangleUV[indexSwap[1]];
						regionMeshSubdivided.uvs[1 + (3 * 3) + subdividedVertexIndex] = rotatedTriangleUV[2];
						regionMeshSubdivided.uvs[2 + (3 * 3) + subdividedVertexIndex] = rotatedTriangleUV[indexSwap[0]];
					} else {
						int8[4] indexSwap = regionFace.flipped ? .(1,0,3,2) : .(0,1,2,3);

						regionMesh.uvs[0 + vertexIndex] = triangleUV[indexSwap[0]];
						regionMesh.uvs[1 + vertexIndex] = triangleUV[2];
						regionMesh.uvs[2 + vertexIndex] = triangleUV[indexSwap[1]];

						regionMesh.uvs[3 + vertexIndex] = triangleUV[indexSwap[2]];
						regionMesh.uvs[4 + vertexIndex] = triangleUV[0];
						regionMesh.uvs[5 + vertexIndex] = triangleUV[indexSwap[3]];

						for (let qi < 4) {
							let offset = (1 + qi) * 4;
							
							regionMeshSubdivided.uvs[0 + (qi * 6) + subdividedVertexIndex] = triangleUV[indexSwap[0] + offset];
							regionMeshSubdivided.uvs[1 + (qi * 6) + subdividedVertexIndex] = triangleUV[2 + offset];
							regionMeshSubdivided.uvs[2 + (qi * 6) + subdividedVertexIndex] = triangleUV[indexSwap[1] + offset];

							regionMeshSubdivided.uvs[3 + (qi * 6) + subdividedVertexIndex] = triangleUV[indexSwap[2] + offset];
							regionMeshSubdivided.uvs[4 + (qi * 6) + subdividedVertexIndex] = triangleUV[0 + offset];
							regionMeshSubdivided.uvs[5 + (qi * 6) + subdividedVertexIndex] = triangleUV[indexSwap[3] + offset];
						}

						i++;
					}
				}
				
				regionMesh.SetDirty();
				regionMeshSubdivided.SetDirty();
			}
		} 
	}
}
