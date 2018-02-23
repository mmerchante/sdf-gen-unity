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
			#define EPSILON .015
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
			float fBox(float3 p) {
				float3 d = abs(p) - .5;
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

			//#define USE_GENERATED

			// START_GEN
			float sdf_generated(float3 p)
			{
				float3 wsPos = float3(.0, .0, .0);
				float stack[12];
				float3 pStack[12];
				pStack[0] = p;
				pStack[0] = (pStack[0] * float3(1.0, .98, 1.0)) - float3(.0, .0, .0);
				pStack[1] = pStack[0];
				pStack[2] = mul(float4x4(.999, .0, -.055, -1.509, .0, 1.0, .0, .14, .055, .0, .999, .498, .0, .0, .0, 1.0), float4(pStack[1], 1.0)).xyz;
				pStack[2].xz = pModPolar(pStack[2].xz, 8.0);
				pStack[3] = mul(float4x4(.795, -.491, -1.401, -.397, .934, 1.642, -.045, -.911, 2.28, -1.25, 1.732, -7.876, .0, .0, .0, 1.0), float4(pStack[2], 1.0)).xyz;
				wsPos = mul(float4x4(.5, .0, .0, -.8, .0, .137, .029, -.064, .0, -.104, .489, .867, .0, .0, .0, 1.0), float4(pStack[3], 1.0)).xyz;
				stack[3] = fBox(wsPos);
				wsPos = mul(float4x4(1.128, -.926, 1.235, -.769, .386, .053, -.313, -1.532, .417, 1.543, .775, -2.843, .0, .0, .0, 1.0), float4(pStack[3], 1.0)).xyz;
				stack[3] = max(stack[3], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.008, -1.259, 1.027, 4.273, .237, .149, .415, -.714, -1.253, 1.228, .275, -.96, .0, .0, .0, 1.0), float4(pStack[3], 1.0)).xyz;
				stack[3] = max(stack[3], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.633, .244, -.964, 3.007, -.219, .173, .415, -.072, .498, 1.651, -.425, -3.193, .0, .0, .0, 1.0), float4(pStack[3], 1.0)).xyz;
				stack[3] = max(stack[3], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-.526, -1.791, .411, 5.514, -.46, .161, .112, .189, -.495, -.242, -1.689, 1.112, .0, .0, .0, 1.0), float4(pStack[3], 1.0)).xyz;
				stack[3] = max(stack[3], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				stack[2] = stack[3];
				stack[1] = stack[2];
				pStack[4] = mul(float4x4(.788, -.135, -.418, 1.929, .097, .792, -.073, -6.665, .425, .022, .795, -.972, .0, .0, .0, 1.0), float4(pStack[1], 1.0)).xyz;
				pStack[5] = pStack[4];
				pStack[6] = pStack[5];
				wsPos = mul(float4x4(.203, -.057, -.028, -.895, .084, .293, .013, .281, .048, -.032, .407, 1.418, .0, .0, .0, 1.0), float4(pStack[6], 1.0)).xyz;
				stack[6] = fBox(wsPos);
				wsPos = mul(float4x4(.149, .07, .135, -.128, .025, .222, -.143, .448, -.291, .18, .228, .615, .0, .0, .0, 1.0), float4(pStack[6], 1.0)).xyz;
				stack[6] = min(stack[6], fBox(wsPos));
				stack[5] = stack[6];
				wsPos = mul(float4x4(.163, -.015, -.23, -.815, -.007, .102, -.012, .176, .238, .035, .166, -.268, .0, .0, .0, 1.0), float4(pStack[5], 1.0)).xyz;
				stack[5] = max(-stack[5], fBox(wsPos));
				stack[4] = stack[5];
				wsPos = mul(float4x4(1.68, -.871, -.276, -5.624, -.01, .133, -.482, -1.2, .848, 1.509, .4, .976, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.288, -1.377, .314, 2.367, -.085, .184, .457, .783, -1.277, 1.044, -.658, 2.615, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-.526, -1.791, .411, 1.346, -.46, .161, .112, .968, -.495, -.242, -1.689, -.74, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(.649, -1.578, .862, .804, .468, .171, -.04, -1.56, -.157, .798, 1.579, 3.123, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-.446, -1.751, .016, -1.128, -.32, .078, -.369, -.361, 1.219, -.321, -1.124, -6.142, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(1.533, -.87, -.329, -4.104, .154, .377, -.281, -1.442, .696, .718, 1.342, -.118, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(1.853, .221, -.392, -1.772, -.102, -.014, -.489, -1.406, -.211, 1.757, -.008, 6.376, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-.556, -.17, -1.815, -1.992, -.453, -.141, .152, -.067, -.525, 1.687, .003, 6.05, .0, .0, .0, 1.0), float4(pStack[4], 1.0)).xyz;
				stack[4] = max(stack[4], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				stack[1] = min(stack[1], stack[4]);
				pStack[7] = mul(float4x4(-.943, -.107, -.059, 1.858, -.128, 1.049, .146, .33, .043, .137, -.94, -1.42, .0, .0, .0, 1.0), float4(pStack[1], 1.0)).xyz;
				pStack[7].xz = pModPolar(pStack[7].xz, 10.0);
				wsPos = mul(float4x4(.7, -.117, -.161, -1.761, .065, .263, .092, -.553, .111, -.261, .671, -.067, .0, .0, .0, 1.0), float4(pStack[7], 1.0)).xyz;
				stack[7] = fBox(wsPos);
				wsPos = mul(float4x4(1.676, -1.862, 1.213, -3.822, .466, .058, -.556, -1.844, 1.232, 1.912, 1.231, -6.583, .0, .0, .0, 1.0), float4(pStack[7], 1.0)).xyz;
				stack[7] = max(stack[7], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.467, -1.788, 1.549, 6.023, .491, .06, .534, -1.973, -1.337, 1.971, 1.009, -.383, .0, .0, .0, 1.0), float4(pStack[7], 1.0)).xyz;
				stack[7] = max(stack[7], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-2.494, .951, -.79, 6.624, -.141, .2, .686, -.322, 1.034, 2.324, -.467, -6.471, .0, .0, .0, 1.0), float4(pStack[7], 1.0)).xyz;
				stack[7] = max(stack[7], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.116, -2.513, .432, 7.905, -.568, .31, .334, .708, -1.242, .163, -2.263, 4.921, .0, .0, .0, 1.0), float4(pStack[7], 1.0)).xyz;
				stack[7] = max(stack[7], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				stack[1] = min(stack[1], stack[7]);
				pStack[8] = mul(float4x4(-.025, -.454, -1.912, .038, -.278, 1.573, -.37, -4.893, 1.937, .319, -.101, -1.369, .0, .0, .0, 1.0), float4(pStack[1], 1.0)).xyz;
				pStack[8].xz = pModPolar(pStack[8].xz, 5.0);
				wsPos = mul(float4x4(.326, -.106, -.365, -1.141, .111, .197, .042, -.145, .293, -.236, .33, -1.004, .0, .0, .0, 1.0), float4(pStack[8], 1.0)).xyz;
				stack[8] = fBox(wsPos);
				wsPos = mul(float4x4(1.01, -1.623, .032, -4.952, .023, .004, -.499, -.781, 1.506, .939, .078, -2.879, .0, .0, .0, 1.0), float4(pStack[8], 1.0)).xyz;
				stack[8] = max(stack[8], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.354, -.774, 1.106, 2.953, .304, .034, .396, -1.14, -.64, 1.62, .35, 2.649, .0, .0, .0, 1.0), float4(pStack[8], 1.0)).xyz;
				stack[8] = max(stack[8], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.462, .892, -.851, 6.541, -.104, .238, .427, .212, 1.084, 1.325, -.474, -.951, .0, .0, .0, 1.0), float4(pStack[8], 1.0)).xyz;
				stack[8] = max(stack[8], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.166, -1.442, .463, 3.098, -.349, .328, .142, 1.04, -.663, .007, -1.648, 2.74, .0, .0, .0, 1.0), float4(pStack[8], 1.0)).xyz;
				stack[8] = max(stack[8], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(.024, -1.723, .829, .498, .494, -.028, -.074, -2.115, .28, .764, 1.579, -.172, .0, .0, .0, 1.0), float4(pStack[8], 1.0)).xyz;
				stack[8] = max(stack[8], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				stack[1] = min(stack[1], stack[8]);
				pStack[9] = mul(float4x4(.795, .302, .647, -.378, .0, 3.241, -1.512, -3.143, -.714, .336, .721, .939, .0, .0, .0, 1.0), float4(pStack[1], 1.0)).xyz;
				pStack[9].xz = pModPolar(pStack[9].xz, 6.0);
				pStack[10] = mul(float4x4(.28, -.047, -1.66, 1.505, .504, 1.821, .033, 4.294, 2.966, -.83, .523, -7.819, .0, .0, .0, 1.0), float4(pStack[9], 1.0)).xyz;
				wsPos = mul(float4x4(.5, .0, .0, -.805, .0, .137, .029, -.247, .0, -.104, .489, .582, .0, .0, .0, 1.0), float4(pStack[10], 1.0)).xyz;
				stack[10] = fBox(wsPos);
				wsPos = mul(float4x4(1.128, -.926, 1.235, -.769, .386, .053, -.313, -1.532, .417, 1.543, .775, -2.843, .0, .0, .0, 1.0), float4(pStack[10], 1.0)).xyz;
				stack[10] = max(stack[10], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.008, -1.259, 1.027, 4.273, .237, .149, .415, -.714, -1.253, 1.228, .275, -.96, .0, .0, .0, 1.0), float4(pStack[10], 1.0)).xyz;
				stack[10] = max(stack[10], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.633, .244, -.964, 3.007, -.219, .173, .415, -.072, .498, 1.651, -.425, -3.193, .0, .0, .0, 1.0), float4(pStack[10], 1.0)).xyz;
				stack[10] = max(stack[10], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-.526, -1.791, .411, 5.514, -.46, .161, .112, .189, -.495, -.242, -1.689, 1.112, .0, .0, .0, 1.0), float4(pStack[10], 1.0)).xyz;
				stack[10] = max(stack[10], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				stack[9] = stack[10];
				stack[1] = min(stack[1], stack[9]);
				pStack[11] = mul(float4x4(1.43, -.092, .828, -1.382, -.088, 1.769, .35, -4.146, -1.481, -.567, 2.494, -2.058, .0, .0, .0, 1.0), float4(pStack[1], 1.0)).xyz;
				wsPos = mul(float4x4(.461, -.193, -.02, -.378, .046, .102, .084, -.212, -.065, -.182, .259, .663, .0, .0, .0, 1.0), float4(pStack[11], 1.0)).xyz;
				stack[11] = fBox(wsPos);
				wsPos = mul(float4x4(1.128, -.926, 1.235, -.769, .386, .053, -.313, -1.532, .417, 1.543, .775, -2.843, .0, .0, .0, 1.0), float4(pStack[11], 1.0)).xyz;
				stack[11] = max(stack[11], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.008, -1.259, 1.027, 4.057, .237, .149, .415, -.994, -1.253, 1.228, .275, -1.057, .0, .0, .0, 1.0), float4(pStack[11], 1.0)).xyz;
				stack[11] = max(stack[11], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-1.633, .244, -.964, 3.007, -.219, .173, .415, -.072, .498, 1.651, -.425, -3.193, .0, .0, .0, 1.0), float4(pStack[11], 1.0)).xyz;
				stack[11] = max(stack[11], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				wsPos = mul(float4x4(-.526, -1.791, .411, 5.374, -.46, .161, .112, .102, -.495, -.242, -1.689, 1.328, .0, .0, .0, 1.0), float4(pStack[11], 1.0)).xyz;
				stack[11] = max(stack[11], wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1);
				stack[1] = min(stack[1], stack[11]);
				stack[0] = stack[1];
				stack[0] = max(stack[0], dot(pStack[0] - float3(1.24, .07, 2.43), float3(-.129, -.864, .486)));
				stack[0] = max(stack[0], dot(pStack[0] - float3(-.2, -1.41, 1.48), float3(.107, -.943, -.314)));
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
							dd = fBox(wsPos);
						else if (parameters == 4)
							dd = fCylinder(wsPos);
						else if(parameters == 6)
							dd = wsPos.y + saturate(wsPos.x * .5) * .1 + saturate(wsPos.z + .5) * .1;

						int opType = parentNode.parameters;

						// Ideally, we should carry the scale... (TODO, also depends on uniform scale?)
						// dd /= clamp(node.transform[0][0], .995, 1.0);

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

				return stack[0].sdf * .65;
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
