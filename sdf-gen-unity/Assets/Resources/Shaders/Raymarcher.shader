Shader "Raymarcher"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Tags { "Queue"="Geometry-1" }

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0
			
			#include "UnityCG.cginc"
			
			#define PI 3.14159265
			#define TAU (2*PI)
			#define PHI (sqrt(5)*0.5 + 0.5)

			#define MAX_STEPS 10
			#define MAX_STEPS_F float(MAX_STEPS)

			#define MAX_DISTANCE 100.0
			#define MIN_DISTANCE .5
			#define EPSILON .025
			#define EPSILON_NORMAL .01

			#define MATERIAL_NONE -1

			#define MAX_SHAPE_COUNT 128

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f 
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 worldSpacePosition : TEXCOORD1;
			};

			struct Intersection
			{
				float totalDistance;
				float sdf;
				int materialID;
			};

			struct Camera
			{
				float3 origin;
				float3 direction;
			};

			struct Node
			{
				float4x4 transform;
				int type; 
				int parameters;
				int depth;
				int domainDistortionType;
				float3 domainDistortion;
			};
			 
			uniform int _SDFShapeCount;
			uniform StructuredBuffer<Node> _SceneTree : register(t1);
			uniform RWTexture2D<float> _AccumulationBuffer : register(u1);

			v2f vert (appdata v)
			{
				float2 uv = v.vertex.xy * 2.0;
				float4 ndc = float4(uv.x, uv.y, 1.0, 1.0) * _ProjectionParams.z;

				float4x4 invView = mul(transpose(UNITY_MATRIX_V), unity_CameraInvProjection);
				
				v2f o;
				o.vertex = float4(v.vertex.x * 2.0, -v.vertex.y * 2.0, 1.0, 1.0);
				o.worldSpacePosition = mul(invView, ndc).xyz;
				o.uv = v.uv;
				return o;
			}

			// hg
			float vmax(float3 v) {
				return max(max(v.x, v.y), v.z);
			}

			// hg
			float fBox(float3 p) {
				float3 d = abs(p) - .5;
				return length(max(d, 0.0)) + vmax(min(d, 0.0));
			}

			// hg
			float fCylinder(float3 p) {
				float d = length(p.xz) - .5;
				d = max(d, abs(p.y) - 1.0);
				return d;
			}

			// iq
			float hash(float n)
			{
				return frac(sin(n)*1751.5453);
			}

			struct StackData
			{
				int index;
				float sdf;
				float3 pos;
			};

			#define MAX_STACK 32

			float3 modc(float3 a, float3 b) { return a - b * floor(a / b); }

			float3 domainRepeat(float3 p, float3 size)
			{
				return fmod(abs(p) + size * .5, size) - size * .5;
			}

			float domainRepeat1D(float p, float size)
			{
				return fmod(abs(p) + size * .5, size) - size * .5;
			}

			// This is a straightforward approach to previsualize the actual sdf inside Unity
			// that is dynamic and general enough to edit a scene in a reasonable framerate.
			// An optimized version would have specific code knowing each shape, removing the loop, etc.
			// Ideally, our code generator should generate the optimized code.
			float sdf(float3 p)
			{
				StackData stack[MAX_STACK];
				stack[0].index = 0;
				stack[0].sdf = 1000.0;
				stack[0].pos = mul(_SceneTree[0].transform, float4(p, 1.0)).xyz;

				int stackTop = 1;
				int currentIndex = 1;

				// Although ideally we could bake final transforms into the leaf shapes,
				// Domain transformations require the proper transform at the level of that node,
				// so if we want full flexibility, we need to compose them.
				[loop]
				while(currentIndex < _SDFShapeCount && stackTop > 0 && stackTop < MAX_STACK)
				{
					Node node = _SceneTree[currentIndex];
					int depth = node.depth;
					int type = node.type;

					StackData parentStackData = stack[stackTop - 1];
					Node parentNode = _SceneTree[parentStackData.index];

					// Backtrack
					if (node.depth <= parentNode.depth)
					{
						StackData grandparentStackData = stack[stackTop - 2];
						Node grandparentNode = _SceneTree[parentStackData.index];

						int opType = grandparentNode.parameters;
						float dd = parentStackData.sdf;

						if (opType == 0)
							dd = min(grandparentStackData.sdf, dd);
						else if (opType == 1)
							dd = max(-grandparentStackData.sdf, dd);
						else if (opType == 2)
							dd = max(grandparentStackData.sdf, dd);

						stack[stackTop - 2].sdf = dd;
						stackTop--;
						continue;
					}

					// Hierarchy node
					if (type == 0)
					{
						// We initialize the node
						stack[stackTop].index = currentIndex;
						stack[stackTop].sdf = node.parameters == 2 ? 0.0 : 1000.0; // Make sure we initialize knowing the operation
						stack[stackTop].pos =  mul(node.transform, float4(parentStackData.pos, 1.0)).xyz;

						if (node.domainDistortionType == 1)
							stack[stackTop].pos = domainRepeat(stack[stackTop].pos, node.domainDistortion);
						else if (node.domainDistortionType == 2)
							stack[stackTop].pos.x = domainRepeat1D(stack[stackTop].pos.x, node.domainDistortion.x);
						else if (node.domainDistortionType == 3)
							stack[stackTop].pos.y = domainRepeat1D(stack[stackTop].pos.y, node.domainDistortion.y);
						else if (node.domainDistortionType == 4)
							stack[stackTop].pos.z = domainRepeat1D(stack[stackTop].pos.z, node.domainDistortion.z);
						
						stackTop++;
					} 
					else if (type == 1)
					{
						int parameters = node.parameters;
						float3 wsPos = mul(node.transform, float4(parentStackData.pos, 1.0)).xyz;

						float dd = 0.0;

						if (parameters == 1)
							dd = wsPos.y;
						else if (parameters == 2)
							dd = length(wsPos) - .5;
						else if (parameters == 3)
							dd = fBox(wsPos);
						else if (parameters == 4)
							dd = fCylinder(wsPos);

						int opType = parentNode.parameters;

						if (opType == 0)
							dd = min(parentStackData.sdf, dd);
						else if (opType == 1)
							dd = max(-parentStackData.sdf, dd);
						else if (opType == 2)
							dd = max(parentStackData.sdf, dd);

						// For now, union
						stack[stackTop - 1].sdf = dd;
					}

					currentIndex++;
				}

				// Last backtrack
				while (stackTop > 1)
				{
					StackData parentStackData = stack[stackTop - 2];
					Node parentNode = _SceneTree[parentStackData.index];

					int opType = parentNode.parameters;
					float dd = stack[stackTop - 1].sdf;

					if (opType == 0)
						dd = min(parentStackData.sdf, dd);
					else if (opType == 1)
						dd = max(-parentStackData.sdf, dd);
					else if (opType == 2)
						dd = max(parentStackData.sdf, dd);

					stack[stackTop - 2].sdf = dd;
					--stackTop;
				}

				return stack[0].sdf;
			}

			// Don't use this ;)
			float3 sdfNormal(float3 p, float epsilon)
			{
				float3 eps = float3(epsilon, -epsilon, 0.0);

				float dX = sdf(p + eps.xzz) - sdf(p + eps.yzz);
				float dY = sdf(p + eps.zxz) - sdf(p + eps.zyz);
				float dZ = sdf(p + eps.zzx) - sdf(p + eps.zzy);

				return normalize(float3(dX, dY, dZ));
			}

			Intersection Raymarch(Camera camera, float2 uv)
			{
				Intersection outData;
				outData.materialID = MATERIAL_NONE;
				outData.sdf = MIN_DISTANCE;
				
				uint2 index = uint2(_ScreenParams.xy * uv);
				outData.totalDistance = _AccumulationBuffer.Load(index) - EPSILON;

				for (int j = 0; j < MAX_STEPS; ++j)
				{
					float3 p = camera.origin + camera.direction * outData.totalDistance;
					outData.sdf = sdf(p);
					
					outData.totalDistance += outData.sdf;

					if (outData.sdf < EPSILON || outData.totalDistance > MAX_DISTANCE)
						break;
				}

				if (outData.sdf < EPSILON)
					outData.materialID = 1;

				_AccumulationBuffer[index] = lerp(_AccumulationBuffer.Load(index), outData.totalDistance, .75);

				return outData;
			}

			float3 Render(Camera camera, Intersection isect, float2 uv)
			{
				float3 p = camera.origin + camera.direction * isect.totalDistance;

				if (isect.materialID > 0)
				{
					// Normals are expensive!
					float3 lightDir = -_WorldSpaceLightPos0.xyz;
					float3 dir = normalize(camera.direction * .5 - lightDir);
					float cosTheta = dot(sdfNormal(p, EPSILON_NORMAL), lightDir);// sdf(p - dir * (.25 + hash(length(p)) * .02)) / .25;
					return cosTheta;
				}

				return 0.0;
			}

			float3 hash3(float n)
			{
				return frac(sin(float3(n, n + 1.0, n + 2.0))*float3(43758.5453123, 22578.1459123, 19642.3490423));
			}

			float4 frag (v2f i) : SV_Target
			{
				Camera camera;
				camera.origin = _WorldSpaceCameraPos;
				camera.direction = normalize(i.worldSpacePosition - camera.origin);

				Intersection isect = Raymarch(camera, i.uv);
				float3 color = Render(camera, isect, i.uv);

				return float4(pow(color, .45454), 1.0);
			}
			ENDCG
		}
	}
}
