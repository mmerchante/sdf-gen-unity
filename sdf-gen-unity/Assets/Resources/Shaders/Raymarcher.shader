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

			#define MAX_STEPS 5
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

			//#define USE_GENERATED

			// START_GEN
			float sdf_generated(float3 p)
			{
				float stack[11];
				float3 wsPos = float3(.0, .0, .0);
				{
					{
						{
							wsPos = mul(float4x4(.366212, -.018295, -.339606, -1.647642, .056539, .169365, .045784, -.036289, .31752, -.121072, .353251, 1.376488, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[2] = fBox(wsPos);
							wsPos = p;
							stack[2] = max(stack[2], dot(p - float3(.749649, .503708, -5.371844), float3(.112289, .017677, -.993519)));
							wsPos = p;
							stack[2] = max(stack[2], dot(p - float3(.61729, 1.512119, -3.314844), float3(.5153, .217051, .829069)));
							wsPos = p;
							stack[2] = max(stack[2], dot(p - float3(.802939, .492445, -2.898844), float3(-.376661, .412016, .82968)));
							wsPos = p;
							stack[2] = max(stack[2], dot(p - float3(.526381, 2.049003, -3.491844), float3(-.856035, .466161, .223379)));
							wsPos = p;
							stack[2] = max(stack[2], dot(p - float3(1.690372, 2.644854, -4.511844), float3(.979357, .185937, -.07929)));
						}
						stack[1] = stack[2];
						{
							wsPos = mul(float4x4(.72864, -.246802, .276958, -.450663, .01411, .14755, .181697, .430409, -.423594, -.40193, .518351, 2.332816, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[3] = fBox(wsPos);
							wsPos = p;
							stack[3] = max(stack[3], dot(p - float3(2.511777, -.250167, -2.730594), float3(.984155, .066357, -.164427)));
							wsPos = p;
							stack[3] = max(stack[3], dot(p - float3(1.502726, .263518, -2.33879), float3(.055411, -.295633, .953693)));
							wsPos = p;
							stack[3] = max(stack[3], dot(p - float3(1.486288, -.383573, -2.310721), float3(-.726848, .088256, .681105)));
							wsPos = p;
							stack[3] = max(stack[3], dot(p - float3(1.502964, .588913, -2.332889), float3(-.856543, .513946, .046833)));
						}
						stack[1] = min(stack[1], stack[3]);
						{
							wsPos = mul(float4x4(.832009, -.00594, -.129228, -.726434, .040007, .079406, .251501, .564192, .120626, -.990067, .852354, 1.375447, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[4] = fBox(wsPos);
							wsPos = p;
							stack[4] = max(stack[4], dot(p - float3(1.298941, -.585941, -2.532126), float3(.716896, .53316, -.449223)));
							wsPos = p;
							stack[4] = max(stack[4], dot(p - float3(.493912, -.555864, -1.885752), float3(.582278, -.430485, .689663)));
							wsPos = p;
							stack[4] = max(stack[4], dot(p - float3(.640882, -1.025121, -2.121249), float3(-.312731, -.390831, .865708)));
							wsPos = p;
							stack[4] = max(stack[4], dot(p - float3(.421833, -.321373, -1.753144), float3(-.849091, .052978, .525584)));
						}
						stack[1] = min(stack[1], stack[4]);
						{
							wsPos = mul(float4x4(-.482537, -.246803, -.612198, -3.183828, .081323, .14755, -.163093, -1.086044, .629838, -.401931, -.226778, -1.7168, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[5] = fBox(wsPos);
							wsPos = p;
							stack[5] = max(stack[5], dot(p - float3(.19784, -.250165, -6.37466), float3(-.928637, .066356, -.365008)));
							wsPos = p;
							stack[5] = max(stack[5], dot(p - float3(1.264739, .26352, -6.19187), float3(.442846, -.295633, -.846457)));
							wsPos = p;
							stack[5] = max(stack[5], dot(p - float3(1.293269, -.38357, -6.207492), float3(.973615, .088256, -.210439)));
							wsPos = p;
							stack[5] = max(stack[5], dot(p - float3(1.267568, .588914, -6.197054), float3(.758722, .513946, .400251)));
						}
						stack[1] = min(stack[1], stack[5]);
						{
							wsPos = mul(float4x4(-.43241, .152275, -.163226, -.711853, .128951, .271778, -.004386, .117215, .120371, -.126451, -.476449, -2.34756, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[6] = fBox(wsPos);
							wsPos = p;
							stack[6] = max(stack[6], dot(p - float3(-1.194891, -.503562, -4.373263), float3(-.898998, .249303, .36007)));
							wsPos = p;
							stack[6] = max(stack[6], dot(p - float3(.820121, -.522973, -5.039686), float3(.600546, .219556, -.768857)));
							wsPos = p;
							stack[6] = max(stack[6], dot(p - float3(.931056, -1.110529, -5.546987), float3(.995711, .082101, .042658)));
							wsPos = p;
							stack[6] = max(stack[6], dot(p - float3(.795582, -.22158, -4.797631), float3(.664419, .079986, .743068)));
							wsPos = p;
							stack[6] = max(stack[6], dot(p - float3(-.437251, .797737, -5.247678), float3(-.370875, .532148, -.761098)));
						}
						stack[1] = min(stack[1], stack[6]);
						{
							wsPos = mul(float4x4(.69886, .036791, .802518, 3.990405, -.15947, .169436, .125945, .374532, -.567731, -.561011, .537203, 1.141397, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[7] = fBox(wsPos);
							wsPos = p;
							stack[7] = max(stack[7], dot(p - float3(-.650824, -.599787, -3.524536), float3(.859323, .44581, .250635)));
							wsPos = p;
							stack[7] = max(stack[7], dot(p - float3(-1.564743, -.569118, -3.668989), float3(-.336327, -.148009, .930042)));
							wsPos = p;
							stack[7] = max(stack[7], dot(p - float3(-1.447638, -1.079286, -3.553815), float3(-.954715, -.147604, .258326)));
							wsPos = p;
							stack[7] = max(stack[7], dot(p - float3(-1.637019, -.312773, -3.715618), float3(-.877347, .1206, -.464456)));
						}
						stack[1] = min(stack[1], stack[7]);
						{
							wsPos = mul(float4x4(.865188, .044144, -.351158, -1.072629, .049106, .159697, .154398, .572379, .309572, -.446085, .669405, 2.302118, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[8] = fBox(wsPos);
							wsPos = p;
							stack[8] = max(stack[8], dot(p - float3(.449836, -.334953, -3.939032), float3(.499422, .416206, -.759836)));
							wsPos = p;
							stack[8] = max(stack[8], dot(p - float3(-.050219, -.244362, -3.013928), float3(.772567, -.067288, .631358)));
							wsPos = p;
							stack[8] = max(stack[8], dot(p - float3(.138361, -.820766, -3.06458), float3(-.064952, -.079834, .99469)));
							wsPos = p;
							stack[8] = max(stack[8], dot(p - float3(-.137959, .047406, -2.969878), float3(-.733238, .134687, .6665)));
						}
						stack[1] = min(stack[1], stack[8]);
						{
							wsPos = mul(float4x4(-.770762, -.15745, -.271417, -1.673138, .083378, .023767, -.259721, -1.497699, .495798, -1.0977, -.348205, -3.165577, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[9] = fBox(wsPos);
							wsPos = p;
							stack[9] = max(stack[9], dot(p - float3(-.727597, -1.311225, -5.861403), float3(-.905304, .404847, -.128545)));
							wsPos = p;
							stack[9] = max(stack[9], dot(p - float3(.285524, -1.184655, -6.035689), float3(-.083937, -.710598, -.698574)));
							wsPos = p;
							stack[9] = max(stack[9], dot(p - float3(.084253, -1.609923, -5.790345), float3(.760439, -.470679, -.447431)));
							wsPos = p;
							stack[9] = max(stack[9], dot(p - float3(.392658, -.976805, -6.171276), float3(.984393, .164067, -.063666)));
						}
						stack[1] = min(stack[1], stack[9]);
						{
							wsPos = mul(float4x4(-.347782, .413738, .62827, 3.66411, -.210966, .084604, -.305156, -1.838639, -.193169, -.665307, -.29571, -2.086563, .0, .0, .0, 1.0), float4(p, 1.0)).xyz;
							stack[10] = fBox(wsPos);
							wsPos = p;
							stack[10] = max(stack[10], dot(p - float3(-.429519, -.154371, -5.264673), float3(-.117752, .746052, .655394)));
							wsPos = p;
							stack[10] = max(stack[10], dot(p - float3(-.4436, -.573437, -6.214905), float3(-.553117, -.63726, -.53662)));
							wsPos = p;
							stack[10] = max(stack[10], dot(p - float3(-.468024, -1.200169, -5.90266), float3(.197589, -.301093, -.9329)));
							wsPos = p;
							stack[10] = max(stack[10], dot(p - float3(-.436711, -.263316, -6.388266), float3(.615924, .315929, -.721683)));
							wsPos = p;
							stack[10] = max(stack[10], dot(p - float3(-1.559114, -.040469, -5.943851), float3(-.977002, -.072851, .200399)));
						}
						stack[1] = min(stack[1], stack[10]);
					}
					stack[0] = stack[1];
					wsPos = p;
					stack[0] = max(stack[0], dot(p - float3(.831366, -1.651262, -.96502), float3(.0, -.990697, -.136091)));
				}
				return stack[0];
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
							float dd = sdfOperation(parentStackData.sdf, grandparentStackData.sdf, opType);

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

						// For now, union
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

			Intersection Raymarch(Camera camera, float2 uv)
			{
				Intersection outData;
				outData.materialID = MATERIAL_NONE;
				outData.sdf = 0.0;
				
				uint2 index = uint2(_ScreenParams.xy * uv);
				outData.totalDistance = max(MIN_DISTANCE, _AccumulationBuffer.Load(index) - EPSILON);

				if (outData.totalDistance < MAX_DISTANCE)
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
				}

				_AccumulationBuffer[index] = lerp(_AccumulationBuffer.Load(index), outData.totalDistance, .95);

				return outData;
			}

			float3 Render(Camera camera, Intersection isect, float2 uv)
			{
				float3 p = camera.origin + camera.direction * isect.totalDistance;

				if (isect.materialID > 0)
				{
					// Normals are expensive!
					float3 lightDir = .57575;
					return dot(sdfNormal(p, EPSILON_NORMAL), lightDir)  *.5 + .5;
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
