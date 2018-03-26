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

			#define USE_GENERATED

			// START_GEN
			
			float sdf_generated(float3 p)
			{
				float3 wsPos = float3(.0,.0,.0);
				float stack[47];
				float4 pStack[47];
				pStack[0] = float4(p, 1.0);
				pStack[0].xz = abs(pStack[0].xz) * float2(-1.0,1.0);
				stack[0] = (dot(pStack[0].xyz - float3(-4.679,-2.361,.0), float3(.0,1.0,.0))*2);
				pStack[1] = mul(float4x4(1.939, -.721, .0, 13.419, -1.103, -2.966, .0, 20.625, .0, .0, -3.164, 13.175, .0, .0, .0, 1.0),pStack[0]);
				pStack[1].z = domainRepeat1D(pStack[1].z , 1.0);
				pStack[2] = pStack[1] - float4(1.14,.0,.0,.0);
				wsPos = mul(float4x4(.0, 1.0, .0, -.085, -1.0, .0, .0, .06, .0, .0, 1.26, .036, .0, .0, .0, 1.0),pStack[2]).xyz;
				stack[2] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.0, 1.0, .0, -.013, -1.0, .0, .0, -.048, .0, .0, 1.0, .0, .0, .0, .0, 1.0),pStack[2]).xyz;
				stack[2] = max(-stack[2],(fCylinder(wsPos)*1));
				wsPos = mul(float4x4(1.0, .0, .0, -1.302, .0, 1.0, .0, .545, .0, .0, .753, .0, .0, .0, .0, 1.0),pStack[1]).xyz;
				stack[1] = max(stack[2],(fBox(wsPos)*1));
				stack[0] = min(stack[0],stack[1]);
				pStack[3] = mul(float4x4(.0, .0, -1.0, 10.36, .0, 1.0, .0, .0, 1.0, .0, .0, 1.32, .0, .0, .0, 1.0),pStack[0]);
				pStack[4] = (pStack[3] * float4(.6,1.0,2.223,1.0)) - float4(.606,5.31,1.202,.0);
				pStack[4].z = domainRepeat1D(pStack[4].z , 4.0);
				wsPos = mul(float4x4(1.0, .0, .0, .0, .0, 1.0, .0, .0, .0, .0, 1.0, .0, .0, .0, .0, 1.0),pStack[4]).xyz;
				stack[4] = (fBox(wsPos)*1);
				wsPos = mul(float4x4(1.265, .0, .0, .412, .0, 1.265, .0, .0, .0, .0, 1.265, .0, .0, .0, .0, 1.0),pStack[4]).xyz;
				stack[4] = min(stack[4],(fBox(wsPos)*1));
				wsPos = mul(float4x4(.333, .0, .0, .427, .0, .264, .0, -1.685, .0, .0, .075, -.022, .0, .0, .0, 1.0),pStack[3]).xyz;
				stack[3] = max(-stack[4],(fBox(wsPos)*1));
				stack[0] = min(stack[0],stack[3]);
				pStack[5] = pStack[0] - float4(-3.52,.0,3.5,.0);
				pStack[6] = (pStack[5] * float4(.63,1.0,2.223,1.0)) - float4(.597,5.31,1.202,.0);
				pStack[6].z = domainRepeat1D(pStack[6].z , 4.0);
				wsPos = mul(float4x4(1.0, .0, .0, .0, .0, 1.0, .0, .0, .0, .0, 1.0, .0, .0, .0, .0, 1.0),pStack[6]).xyz;
				stack[6] = (fBox(wsPos)*1);
				wsPos = mul(float4x4(1.265, .0, .0, .412, .0, 1.265, .0, .0, .0, .0, 1.265, .0, .0, .0, .0, 1.0),pStack[6]).xyz;
				stack[6] = min(stack[6],(fBox(wsPos)*1));
				wsPos = mul(float4x4(1.0, .0, .0, .0, .0, 1.769, .0, -3.397, .0, .0, 1.636, -2.978, .0, .0, .0, 1.0),pStack[6]).xyz;
				stack[6] = min(stack[6],(fBox(wsPos)*0.35));
				wsPos = mul(float4x4(.333, .0, .0, .427, .0, .264, .0, -1.685, .0, .0, .075, -.022, .0, .0, .0, 1.0),pStack[5]).xyz;
				stack[5] = max(-stack[6],(fBox(wsPos)*1));
				stack[0] = min(stack[0],stack[5]);
				pStack[7] = pStack[0] - float4(-3.309,.0,3.5,.0);
				wsPos = mul(float4x4(.333, .0, .0, .296, .0, 5.018, .0, -4.953, .0, .0, .075, -.05, .0, .0, .0, 1.0),pStack[7]).xyz;
				stack[7] = (fBox(wsPos)*1);
				wsPos = mul(float4x4(.333, .0, .0, .284, .0, 10.349, .0, -10.69, .0, .0, .075, -.022, .0, .0, .0, 1.0),pStack[7]).xyz;
				stack[7] = min(stack[7],(fBox(wsPos)*1));
				pStack[8] = pStack[7] - float4(.463,.909,1.179,.0);
				pStack[8].z = domainRepeat1D(pStack[8].z , 2.35);
				wsPos = mul(float4x4(.0, 5.945, .0, 1.07, 12.343, .0, .0, -1.605, .0, .0, 5.945, .0, .0, .0, .0, 1.0),pStack[8]).xyz;
				stack[8] = (fCylinder(wsPos)*0.34);
				wsPos = mul(float4x4(-22.09, 38.956, .0, -112.745, -2.115, -1.199, .0, 4.879, .0, .0, 44.783, .0, .0, .0, .0, 1.0),pStack[8]).xyz;
				stack[8] = min(stack[8],(fCylinder(wsPos)*0.05));
				wsPos = mul(float4x4(.0, 9.971, .0, -29.914, -22.022, .0, .0, 3.568, .0, .0, 9.971, .0, .0, .0, .0, 1.0),pStack[8]).xyz;
				stack[8] = min(stack[8],(fCylinder(wsPos)*0.1));
				stack[7] = min(stack[7],stack[8]);
				pStack[9] = pStack[7];
				wsPos = mul(float4x4(.333, .0, .0, .197, .0, .25, .0, .198, .0, .0, .085, .0, .0, .0, .0, 1.0),pStack[9]).xyz;
				stack[9] = (fBox(wsPos)*1);
				pStack[10] = pStack[9];
				pStack[11] = mul(float4x4(1.0, .0, .0, .0, .0, .0, .242, .0, .0, -1.0, .0, -.518, .0, .0, .0, 1.0),pStack[10]);
				pStack[12] = mul(float4x4(.0, 4.139, .0, .0, -.242, .0, .0, -.313, .0, .0, 1.0, .002, .0, .0, .0, 1.0),pStack[11]);
				pStack[12].x = domainRepeat1D(pStack[12].x , 2.35);
				wsPos = mul(float4x4(.41, .0, .0, .0, .0, 1.87, .0, .626, .0, .0, .41, .0, .0, .0, .0, 1.0),pStack[12]).xyz;
				stack[12] = (fCylinder(wsPos)*0.9);
				pStack[13] = mul(float4x4(1.0, .0, .0, .0, .0, .0, -1.0, -.518, .0, 4.139, .0, .0, .0, .0, .0, 1.0),pStack[11]);
				wsPos = mul(float4x4(.41, .0, .0, .287, .0, .0, .011, .0, .0, -.41, .0, -.213, .0, .0, .0, 1.0),pStack[13]).xyz;
				stack[13] = (fCylinder(wsPos)*0.8);
				wsPos = mul(float4x4(.45, .0, .0, .257, .0, .621, .0, -.141, .0, .0, .051, .0, .0, .0, .0, 1.0),pStack[13]).xyz;
				stack[13] = max(-stack[13],(fBox(wsPos)*1.4));
				stack[11] = max(-stack[12],stack[13]);
				pStack[14] = pStack[10] - float4(.463,-.619,1.179,.0);
				pStack[14].z = domainRepeat1D(pStack[14].z , 2.35);
				wsPos = mul(float4x4(2.0, .0, .0, .0, .0, 11.389, .0, .0, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[14]).xyz;
				stack[14] = (fBox(wsPos)*0.5);
				wsPos = mul(float4x4(3.152, .0, .0, .0, .0, 1.325, .0, 1.182, .0, .0, 3.152, .0, .0, .0, .0, 1.0),pStack[14]).xyz;
				stack[14] = min(stack[14],(fCylinder(wsPos)*0.5));
				wsPos = mul(float4x4(2.0, .0, .0, 4.81, .0, 6.667, .0, .0, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[14]).xyz;
				stack[14] = min(stack[14],(fBox(wsPos)*0.5));
				wsPos = mul(float4x4(2.263, .0, .0, .0, .0, 12.89, .0, 1.173, .0, .0, 2.263, .0, .0, .0, .0, 1.0),pStack[14]).xyz;
				stack[14] = min(stack[14],(fBox(wsPos)*0.5));
				wsPos = mul(float4x4(2.0, .0, .0, .0, .0, 11.39, .0, 19.476, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[14]).xyz;
				stack[14] = min(stack[14],(fBox(wsPos)*0.5));
				stack[10] = min(stack[11],stack[14]);
				pStack[15] = pStack[10] - float4(.083,.0,.0,.0);
				pStack[15].z = domainRepeat1D(pStack[15].z , 2.35);
				pStack[16] = mul(float4x4(.0, .0, 1.0, .0, -.09, .0, .0, .016, .0, -1.0, .0, -.516, .0, .0, .0, 1.0),pStack[15]);
				wsPos = mul(float4x4(.35, .0, .0, .0, .0, 5.733, .0, .0, .0, .0, .35, .0, .0, .0, .0, 1.0),pStack[16]).xyz;
				stack[16] = (fCylinder(wsPos)*0.9);
				wsPos = mul(float4x4(.437, .0, .0, .0, .0, 3.686, .0, .0, .0, .0, .437, .0, .0, .0, .0, 1.0),pStack[16]).xyz;
				stack[16] = max(-stack[16],(fCylinder(wsPos)*1.2));
				wsPos = mul(float4x4(1.575, .0, .0, -.926, .0, .791, .0, -.217, .0, .0, .425, .0, .0, .0, .0, 1.0),pStack[15]).xyz;
				stack[15] = max(stack[16],(fBox(wsPos)*1.04));
				stack[10] = min(stack[10],stack[15]);
				stack[9] = max(stack[9],stack[10]);
				stack[7] = min(stack[7],stack[9]);
				stack[0] = min(stack[0],stack[7]);
				pStack[17] = mul(float4x4(.0, .0, -1.0, 9.985, .0, 1.0, .0, -3.412, 1.0, .0, .0, -.421, .0, .0, .0, 1.0),pStack[0]);
				wsPos = mul(float4x4(.333, .0, .0, .325, .0, 5.018, .0, -4.687, .0, .0, .281, .553, .0, .0, .0, 1.0),pStack[17]).xyz;
				stack[17] = (fBox(wsPos)*1);
				wsPos = mul(float4x4(.333, .0, .0, .293, .0, 10.349, .0, -10.142, .0, .0, .281, .553, .0, .0, .0, 1.0),pStack[17]).xyz;
				stack[17] = min(stack[17],(fBox(wsPos)*1));
				pStack[18] = pStack[17];
				wsPos = mul(float4x4(.333, .0, .0, .197, .0, .25, .0, .198, .0, .0, .309, .593, .0, .0, .0, 1.0),pStack[18]).xyz;
				stack[18] = (fBox(wsPos)*1);
				pStack[19] = pStack[18] - float4(.0,.0,.13,.0);
				stack[19] = (dot(pStack[19].xyz - float3(-1.81,-2.04,.0), float3(1.0,.0,.0))*1);
				pStack[20] = mul(float4x4(1.0, .0, .0, .0, .0, .0, .242, .0, .0, -1.0, .0, -.518, .0, .0, .0, 1.0),pStack[19]);
				pStack[21] = mul(float4x4(.0, 1.0, .0, .469, -.242, .0, .0, -.314, .0, .0, 1.0, .0, .0, .0, .0, 1.0),pStack[20]);
				pStack[21].x = domainRepeat1D(pStack[21].x , 1.3);
				wsPos = mul(float4x4(3.07, .0, .0, -.537, .0, 1.59, .0, .157, .0, .0, .713, .0, .0, .0, .0, 1.0),pStack[21]).xyz;
				stack[21] = (fCylinder(wsPos)*1);
				pStack[22] = mul(float4x4(1.0, .0, .0, .0, .0, .0, -1.0, -.518, .0, 4.139, .0, .0, .0, .0, .0, 1.0),pStack[20]);
				wsPos = mul(float4x4(.41, .0, .0, .287, .0, .0, .011, .0, .0, -.41, .0, -.389, .0, .0, .0, 1.0),pStack[22]).xyz;
				stack[22] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.45, .0, .0, .257, .0, .621, .0, -.141, .0, .0, .051, .0, .0, .0, .0, 1.0),pStack[22]).xyz;
				stack[22] = max(-stack[22],(fBox(wsPos)*1));
				stack[20] = max(-stack[21],stack[22]);
				stack[19] = min(stack[19],stack[20]);
				pStack[23] = pStack[19] - float4(.46,-.619,.864,.0);
				pStack[23].z = domainRepeat1D(pStack[23].z , 1.4);
				wsPos = mul(float4x4(2.0, .0, .0, .0, .0, 11.389, .0, .0, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[23]).xyz;
				stack[23] = (fBox(wsPos)*0.75);
				wsPos = mul(float4x4(3.899, .0, .0, .0, .0, 1.234, .0, 1.101, .0, .0, 3.899, .0, .0, .0, .0, 1.0),pStack[23]).xyz;
				stack[23] = min(stack[23],(fCylinder(wsPos)*0.75));
				wsPos = mul(float4x4(2.0, .0, .0, 4.81, .0, 6.667, .0, .0, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[23]).xyz;
				stack[23] = min(stack[23],(fBox(wsPos)*0.75));
				wsPos = mul(float4x4(2.263, .0, .0, .0, .0, 12.89, .0, 1.173, .0, .0, 2.263, .0, .0, .0, .0, 1.0),pStack[23]).xyz;
				stack[23] = min(stack[23],(fBox(wsPos)*0.75));
				stack[19] = min(stack[19],stack[23]);
				pStack[24] = (pStack[19] * float4(1.711,1.711,1.711,1.0)) - float4(.351,-.114,.118,.0);
				pStack[24].z = domainRepeat1D(pStack[24].z , 2.35);
				pStack[25] = mul(float4x4(.0, .0, 1.0, .0, -.242, .0, .0, .13, .0, -1.0, .0, -.516, .0, .0, .0, 1.0),pStack[24]);
				wsPos = mul(float4x4(.364, .0, .0, .0, .0, 14.716, .0, .0, .0, .0, .364, .0, .0, .0, .0, 1.0),pStack[25]).xyz;
				stack[25] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.48, .0, .0, .0, .0, 25.9, .0, .0, .0, .0, .48, .0, .0, .0, .0, 1.0),pStack[25]).xyz;
				stack[25] = max(-stack[25],(fCylinder(wsPos)*1));
				wsPos = mul(float4x4(1.0, .0, .0, -.569, .0, .679, .0, -.087, .0, .0, .425, .0, .0, .0, .0, 1.0),pStack[24]).xyz;
				stack[24] = max(stack[25],(fBox(wsPos)*1));
				stack[19] = min(stack[19],stack[24]);
				stack[18] = max(stack[18],stack[19]);
				stack[17] = min(stack[17],stack[18]);
				stack[0] = min(stack[0],stack[17]);
				pStack[26] = mul(float4x4(.0, .0, -1.0, 10.128, .0, 1.0, .0, .0, .87, .0, .0, 1.19, .0, .0, .0, 1.0),pStack[0]);
				wsPos = mul(float4x4(.333, .0, .0, .283, .0, 5.018, .0, -5.028, .0, .0, .167, .0, .0, .0, .0, 1.0),pStack[26]).xyz;
				stack[26] = (fBox(wsPos)*1);
				pStack[27] = pStack[26];
				wsPos = mul(float4x4(.333, .0, .0, .197, .0, .25, .0, .198, .0, .0, .167, .0, .0, .0, .0, 1.0),pStack[27]).xyz;
				stack[27] = (fBox(wsPos)*1);
				pStack[28] = pStack[27];
				stack[28] = (dot(pStack[28].xyz - float3(-1.81,-2.04,.0), float3(1.0,.0,.0))*1);
				pStack[29] = (pStack[28] * float4(1.15,1.0,1.0,1.0)) - float4(.475,-.619,-1.218,.0);
				pStack[29].z = domainRepeat1D(pStack[29].z , 2.35);
				wsPos = mul(float4x4(3.152, .0, .0, .0, .0, 1.325, .0, 1.182, .0, .0, 3.152, -.224, .0, .0, .0, 1.0),pStack[29]).xyz;
				stack[29] = (fCylinder(wsPos)*0.57);
				wsPos = mul(float4x4(2.0, .0, .0, 5.286, .0, 6.667, .0, .0, .0, .0, 2.0, -.142, .0, .0, .0, 1.0),pStack[29]).xyz;
				stack[29] = min(stack[29],(fBox(wsPos)*0.57));
				wsPos = mul(float4x4(2.263, .0, .0, .0, .0, 12.89, .0, 1.173, .0, .0, 2.263, .0, .0, .0, .0, 1.0),pStack[29]).xyz;
				stack[29] = min(stack[29],(fBox(wsPos)*0.57));
				wsPos = mul(float4x4(2.0, .0, .0, .0, .0, 11.39, .0, 19.248, .0, .0, 2.0, -.142, .0, .0, .0, 1.0),pStack[29]).xyz;
				stack[29] = min(stack[29],(fBox(wsPos)*0.57));
				wsPos = mul(float4x4(2.0, .0, .0, .0, .0, 11.389, .0, .0, .0, .0, 2.0, -.142, .0, .0, .0, 1.0),pStack[29]).xyz;
				stack[29] = min(stack[29],(fBox(wsPos)*0.57));
				stack[28] = min(stack[28],stack[29]);
				pStack[30] = mul(float4x4(1.0, .0, .0, .0, .0, .0, .242, .0, .0, -1.0, .0, -.518, .0, .0, .0, 1.0),pStack[28]);
				pStack[31] = mul(float4x4(.0, 4.139, .0, .0, -.242, .0, .0, -.313, .0, .0, 1.0, .002, .0, .0, .0, 1.0),pStack[30]);
				pStack[31].x = domainRepeat1D(pStack[31].x , 2.35);
				wsPos = mul(float4x4(.41, .0, .0, .0, .0, 1.87, .0, .626, .0, .0, .41, .0, .0, .0, .0, 1.0),pStack[31]).xyz;
				stack[31] = (fCylinder(wsPos)*1);
				pStack[32] = mul(float4x4(1.0, .0, .0, .0, .0, .0, -1.0, -.518, .0, 4.139, .0, .0, .0, .0, .0, 1.0),pStack[30]);
				wsPos = mul(float4x4(.41, .0, .0, .287, .0, .0, .011, .0, .0, -.41, .0, -.213, .0, .0, .0, 1.0),pStack[32]).xyz;
				stack[32] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.45, .0, .0, .257, .0, .621, .0, -.141, .0, .0, .051, .0, .0, .0, .0, 1.0),pStack[32]).xyz;
				stack[32] = max(-stack[32],(fBox(wsPos)*1));
				stack[30] = max(-stack[31],stack[32]);
				stack[28] = min(stack[28],stack[30]);
				pStack[33] = pStack[28];
				pStack[33].z = domainRepeat1D(pStack[33].z , 2.35);
				pStack[34] = mul(float4x4(.0, .0, 1.0, .0, -.242, .0, .0, .13, .0, -1.0, .0, -.516, .0, .0, .0, 1.0),pStack[33]);
				wsPos = mul(float4x4(.364, .0, .0, .0, .0, 14.716, .0, .0, .0, .0, .364, .0, .0, .0, .0, 1.0),pStack[34]).xyz;
				stack[34] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.48, .0, .0, .0, .0, 25.9, .0, .0, .0, .0, .48, .0, .0, .0, .0, 1.0),pStack[34]).xyz;
				stack[34] = max(-stack[34],(fCylinder(wsPos)*1));
				wsPos = mul(float4x4(.65, .0, .0, -.37, .0, .791, .0, -.176, .0, .0, .425, .0, .0, .0, .0, 1.0),pStack[33]).xyz;
				stack[33] = max(stack[34],(fBox(wsPos)*1));
				stack[28] = min(stack[28],stack[33]);
				stack[27] = max(stack[27],stack[28]);
				stack[26] = min(stack[26],stack[27]);
				wsPos = mul(float4x4(.333, .0, .0, .252, .0, 10.349, .0, -10.845, .0, .0, .167, .0, .0, .0, .0, 1.0),pStack[26]).xyz;
				stack[26] = min(stack[26],(fBox(wsPos)*1));
				stack[0] = min(stack[0],stack[26]);
				pStack[35] = pStack[0] - float4(-3.309,3.35,3.5,.0);
				wsPos = mul(float4x4(.333, .0, .0, .296, .0, 5.018, .0, -4.953, .0, .0, .075, -.05, .0, .0, .0, 1.0),pStack[35]).xyz;
				stack[35] = (fBox(wsPos)*1);
				wsPos = mul(float4x4(.333, .0, .0, .284, .0, 10.349, .0, -10.69, .0, .0, .075, -.022, .0, .0, .0, 1.0),pStack[35]).xyz;
				stack[35] = min(stack[35],(fBox(wsPos)*1));
				pStack[36] = pStack[35];
				wsPos = mul(float4x4(.333, .0, .0, .197, .0, .25, .0, .198, .0, .0, .085, .0, .0, .0, .0, 1.0),pStack[36]).xyz;
				stack[36] = (fBox(wsPos)*1);
				pStack[37] = pStack[36];
				pStack[38] = mul(float4x4(1.0, .0, .0, .0, .0, .0, .242, .0, .0, -1.0, .0, -.518, .0, .0, .0, 1.0),pStack[37]);
				pStack[39] = mul(float4x4(.0, 4.139, .0, .0, -.242, .0, .0, -.313, .0, .0, 1.0, .002, .0, .0, .0, 1.0),pStack[38]);
				pStack[39].x = domainRepeat1D(pStack[39].x , 2.35);
				wsPos = mul(float4x4(.41, .0, .0, .0, .0, 1.87, .0, .626, .0, .0, .41, .0, .0, .0, .0, 1.0),pStack[39]).xyz;
				stack[39] = (fCylinder(wsPos)*1);
				pStack[40] = mul(float4x4(1.0, .0, .0, .0, .0, .0, -1.0, -.518, .0, 4.139, .0, .0, .0, .0, .0, 1.0),pStack[38]);
				wsPos = mul(float4x4(.41, .0, .0, .287, .0, .0, .011, .0, .0, -.41, .0, -.213, .0, .0, .0, 1.0),pStack[40]).xyz;
				stack[40] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.45, .0, .0, .257, .0, .621, .0, -.141, .0, .0, .051, .0, .0, .0, .0, 1.0),pStack[40]).xyz;
				stack[40] = max(-stack[40],(fBox(wsPos)*1));
				stack[38] = max(-stack[39],stack[40]);
				pStack[41] = pStack[37] - float4(.463,-.619,1.179,.0);
				pStack[41].z = domainRepeat1D(pStack[41].z , 4.7);
				wsPos = mul(float4x4(2.0, .0, .0, .0, .0, 18.877, .0, .302, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[41]).xyz;
				stack[41] = (fCylinder(wsPos)*0.75);
				wsPos = mul(float4x4(3.445, .0, .0, .0, .0, 1.426, .0, 1.227, .0, .0, 3.445, .0, .0, .0, .0, 1.0),pStack[41]).xyz;
				stack[41] = min(stack[41],(fCylinder(wsPos)*0.6));
				wsPos = mul(float4x4(2.0, .0, .0, 4.81, .0, 6.667, .0, .0, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[41]).xyz;
				stack[41] = min(stack[41],(fBox(wsPos)*1));
				wsPos = mul(float4x4(2.263, .0, .0, .0, .0, 21.364, .0, 1.515, .0, .0, 2.263, .0, .0, .0, .0, 1.0),pStack[41]).xyz;
				stack[41] = min(stack[41],(fCylinder(wsPos)*1));
				wsPos = mul(float4x4(2.263, .0, .0, .0, .0, 21.363, .0, 34.2, .0, .0, 2.263, .0, .0, .0, .0, 1.0),pStack[41]).xyz;
				stack[41] = min(stack[41],(fCylinder(wsPos)*1));
				stack[37] = min(stack[38],stack[41]);
				pStack[42] = pStack[37];
				pStack[42].z = domainRepeat1D(pStack[42].z , 2.35);
				pStack[43] = mul(float4x4(.0, .0, 1.0, .0, -.242, .0, .0, .13, .0, -1.0, .0, -.516, .0, .0, .0, 1.0),pStack[42]);
				wsPos = mul(float4x4(.364, .0, .0, .0, .0, 14.716, .0, .0, .0, .0, .364, .0, .0, .0, .0, 1.0),pStack[43]).xyz;
				stack[43] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.48, .0, .0, .0, .0, 25.9, .0, .0, .0, .0, .48, .0, .0, .0, .0, 1.0),pStack[43]).xyz;
				stack[43] = max(-stack[43],(fCylinder(wsPos)*1));
				wsPos = mul(float4x4(1.0, .0, .0, -.569, .0, .791, .0, -.089, .0, .0, .425, .0, .0, .0, .0, 1.0),pStack[42]).xyz;
				stack[42] = max(stack[43],(fBox(wsPos)*1));
				stack[37] = min(stack[37],stack[42]);
				pStack[44] = pStack[37] - float4(.463,-.619,-1.15,.0);
				pStack[44].z = domainRepeat1D(pStack[44].z , 4.7);
				wsPos = mul(float4x4(2.0, .0, .0, .0, .0, 11.389, .0, .0, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[44]).xyz;
				stack[44] = (fBox(wsPos)*0.6);
				wsPos = mul(float4x4(2.394, .0, .0, .065, .0, .71, .0, .578, .0, .0, 2.923, .0, .0, .0, .0, 1.0),pStack[44]).xyz;
				stack[44] = min(stack[44],(fBox(wsPos)*0.65));
				wsPos = mul(float4x4(2.0, .0, .0, 4.81, .0, 6.667, .0, .0, .0, .0, 2.0, .0, .0, .0, .0, 1.0),pStack[44]).xyz;
				stack[44] = min(stack[44],(fBox(wsPos)*0.85));
				wsPos = mul(float4x4(2.263, .0, .0, .0, .0, 12.89, .0, 1.173, .0, .0, 2.263, .0, .0, .0, .0, 1.0),pStack[44]).xyz;
				stack[44] = min(stack[44],(fBox(wsPos)*0.65));
				wsPos = mul(float4x4(2.263, .0, .0, .0, .0, 10.076, .0, 16.333, .0, .0, 2.263, .0, .0, .0, .0, 1.0),pStack[44]).xyz;
				stack[44] = min(stack[44],(fBox(wsPos)*0.65));
				stack[37] = min(stack[37],stack[44]);
				stack[36] = max(stack[36],stack[37]);
				stack[35] = min(stack[35],stack[36]);
				stack[0] = min(stack[0],stack[35]);
				stack[0] = min(stack[0],(dot(pStack[0].xyz - float3(-5.06,-2.04,.0), float3(1.0,.0,.0))*1));
				pStack[45] = mul(float4x4(.0, -.574, -1.84, 24.066, .0, -2.814, .878, 14.11, -2.948, .0, .0, -1.094, .0, .0, .0, 1.0),pStack[0]);
				pStack[45].z = domainRepeat1D(pStack[45].z , 1.0);
				pStack[46] = pStack[45] - float4(1.14,.0,.0,.0);
				wsPos = mul(float4x4(.0, 1.0, .0, -.085, -1.0, .0, .0, .06, .0, .0, 1.26, .036, .0, .0, .0, 1.0),pStack[46]).xyz;
				stack[46] = (fCylinder(wsPos)*1);
				wsPos = mul(float4x4(.0, 1.0, .0, -.013, -1.0, .0, .0, -.048, .0, .0, 1.0, .0, .0, .0, .0, 1.0),pStack[46]).xyz;
				stack[46] = max(-stack[46],(fCylinder(wsPos)*1));
				wsPos = mul(float4x4(1.0, .0, .0, -1.302, .0, 1.0, .0, .545, .0, .0, .753, .0, .0, .0, .0, 1.0),pStack[45]).xyz;
				stack[45] = max(stack[46],(fBox(wsPos)*1));
				stack[0] = min(stack[0],stack[45]);
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
							dd = fBox(wsPos);
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
