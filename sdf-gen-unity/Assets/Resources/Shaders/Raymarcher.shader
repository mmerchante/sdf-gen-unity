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

			#define MAX_STEPS 2
			#define MAX_STEPS_F float(MAX_STEPS)

			#define MAX_DISTANCE 100.0
			#define MIN_DISTANCE .5
			#define EPSILON .005
			#define EPSILON_NORMAL .005	

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
				float bias;
			};
			 
			uniform int _SDFShapeCount;
			uniform StructuredBuffer<Node> _SceneTree : register(t1);
			uniform RWTexture2D<float4> _AccumulationBuffer : register(u1);

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
			float fBox(float3 p, float3 b) {
				float3 d = abs(p) - b;
				return length(max(d, 0.0)) + vmax(min(d, 0.0));
			}

			// hg
			float fCylinder(float3 p) {
				float d = length(p.xz) - .5;
				d = max(d, abs(p.y) - 1.0);
				return d * .5;
			}

			// iq
			float hash(float n)
			{
				return frac(sin(n)*1751.5453);
			}

			float mod(float x, float y)
			{
				return x - y * floor(x / y);
			}

			// hg
			float2 pModPolar(float2 p, float repetitions) {
				float angle = 2.0 * PI / repetitions;
				float a = atan2(p.y, p.x) + angle * .5;
				float r = length(p);

				a = mod(a, angle) - angle * .5;
				return float2(cos(a), sin(a)) * r;
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

			float sdfOperation(float a, float b, int op)
			{
				float d = a;

				if (op == 0)
					d = min(a, b);
				else if (op == 1)
					d = max(-a, b);
				else if (op == 2)
					d = max(a, b);

				return d;
			}

			// #define USE_GENERATED

			// START_GEN		
			float sdf_generated(float3 p)
			{
				return 0.0;
			}
			// END_GEN

			// This is a straightforward approach to previsualize the actual sdf inside Unity
			// that is dynamic and general enough to edit a scene in a reasonable framerate.
			// An optimized version would have specific code knowing each shape, removing the loop, etc.
			// Ideally, our code generator should generate the optimized code.
			float sdf(float3 p)
			{
			#ifdef USE_GENERATED
				return sdf_generated(p);
			#endif

				StackData stack[MAX_STACK];
				stack[0].index = 0;
				stack[0].sdf = 1000.0;
				stack[0].pos = mul(_SceneTree[0].transform, float4(p, 1.0)).xyz;

				int stackTop = 1;
				int currentIndex = 1;

				// Although ideally we could bake final transforms into the leaf shapes,
				// Domain transformations like repeat require the proper transform at the level of that node,
				// so if we want full flexibility, we need to compose them.
				// An optimized shader would just use the baked final transforms until it hits a domain distorted node.
				[loop]
				while(currentIndex < _SDFShapeCount && stackTop > 0 && stackTop < MAX_STACK)
				{
					Node node = _SceneTree[currentIndex];
					int depth = node.depth;
					int type = node.type;

					StackData parentStackData = stack[stackTop - 1];
					Node parentNode = _SceneTree[parentStackData.index];

					{
						// Backtrack
						if (node.depth <= parentNode.depth)
						{
							StackData grandparentStackData = stack[stackTop - 2];
							Node grandparentNode = _SceneTree[grandparentStackData.index];

							int opType = grandparentNode.parameters;
							float dd = sdfOperation(grandparentStackData.sdf, parentStackData.sdf, opType);

							stack[stackTop - 2].sdf = dd;
							stackTop--;
							continue;
						}
					}

					// Hierarchy node
					if (type == 0)
					{
						// We initialize the node
						stack[stackTop].index = currentIndex;
						stack[stackTop].sdf = node.parameters == 2 ? 0.0 : 1000.0; // Make sure we initialize knowing the operation
						stack[stackTop].pos = mul(node.transform, float4(parentStackData.pos, 1.0)).xyz;

						if (node.domainDistortionType == 1)
							stack[stackTop].pos = domainRepeat(stack[stackTop].pos, node.domainDistortion);
						else if (node.domainDistortionType == 2)
							stack[stackTop].pos.x = domainRepeat1D(stack[stackTop].pos.x, node.domainDistortion.x);
						else if (node.domainDistortionType == 3)
							stack[stackTop].pos.y = domainRepeat1D(stack[stackTop].pos.y, node.domainDistortion.y);
						else if (node.domainDistortionType == 4)
							stack[stackTop].pos.z = domainRepeat1D(stack[stackTop].pos.z, node.domainDistortion.z);
						else if (node.domainDistortionType == 5)
							stack[stackTop].pos.yz = pModPolar(stack[stackTop].pos.yz, node.domainDistortion.x);
						else if(node.domainDistortionType == 6)
							stack[stackTop].pos.xz = pModPolar(stack[stackTop].pos.xz, node.domainDistortion.x);
						else if (node.domainDistortionType == 7)
							stack[stackTop].pos.xy = pModPolar(stack[stackTop].pos.xy, node.domainDistortion.x);
						else if(node.domainDistortionType == 8)
							stack[stackTop].pos = abs(stack[stackTop].pos);
						else if(node.domainDistortionType == 9)
							stack[stackTop].pos.xz = abs(stack[stackTop].pos).xz * float2(-1.0, 1.0);
						else if(node.domainDistortionType == 10)
							stack[stackTop].pos.x = abs(stack[stackTop].pos).x;
						else if(node.domainDistortionType == 11)
							stack[stackTop].pos.y = abs(stack[stackTop].pos).y;
						else if(node.domainDistortionType == 12)
							stack[stackTop].pos.z = abs(stack[stackTop].pos).z;
						
						stackTop++;
					} 
					else if (type == 1)
					{
						int parameters = node.parameters;
						float3 wsPos = mul(node.transform, float4(parentStackData.pos, 1.0)).xyz;

						float dd = 1000.0;

						if (parameters == 1)
							dd = wsPos.y;
						else if (parameters == 2)
							dd = length(wsPos) - .5;
						else if (parameters == 3)
							dd = fBox(wsPos, node.domainDistortion);
						else if (parameters == 4)
							dd = fCylinder(wsPos);
						else if(parameters == 6)
							dd = wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1;

						dd *= node.bias;

						int opType = parentNode.parameters;
						stack[stackTop - 1].sdf = sdfOperation(parentStackData.sdf, dd, opType);
					}

					currentIndex++;
				}

				// Last backtrack
				while (stackTop > 1)
				{
					StackData parentStackData = stack[stackTop - 2];
					Node parentNode = _SceneTree[parentStackData.index];

					int opType = parentNode.parameters;
					stack[stackTop - 2].sdf = sdfOperation(parentStackData.sdf, stack[stackTop - 1].sdf, opType);
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

			Intersection Raymarch(Camera camera, float2 uv, out float iterations)
			{
				Intersection outData;
				outData.sdf = 0.0;

				uint2 index = uint2(_ScreenParams.xy * uv);
				float4 accum = _AccumulationBuffer.Load(index);
				
				outData.totalDistance = max(MIN_DISTANCE, accum.x - EPSILON);
				outData.materialID = accum.y;

				if (outData.totalDistance < MAX_DISTANCE * .95)
				{
					if(accum.y < .5)
					{
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

						accum.x = lerp(_AccumulationBuffer.Load(index), outData.totalDistance, .995);
						accum.y = outData.materialID;
						accum.z += 1.f;


						outData.totalDistance -= EPSILON;
					}
				}

				iterations = accum.z;

				_AccumulationBuffer[index] = accum;
				outData.totalDistance -= EPSILON * 4.0;
				return outData;
			}

			float3 Render(Camera camera, Intersection isect, float2 uv)
			{
				float3 p = camera.origin + camera.direction * isect.totalDistance;

				if (isect.materialID > 0)
				{
					// Normals are expensive!
					float3 lightDir = .57575;
					float fakeAO = saturate(sdf(p + lightDir) / .2);
					return dot(sdfNormal(p, EPSILON_NORMAL), lightDir)  *.5 + .5;// fakeAO + .25;
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

				float iterations = 0.0;
				Intersection isect = Raymarch(camera, i.uv, iterations);
				float3 color = Render(camera, isect, i.uv);

				return float4(pow(color, .45454), iterations);
			}
			ENDCG
		}
	}
}
