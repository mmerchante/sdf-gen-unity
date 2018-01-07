Shader "Raymarcher"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Tags { "Queue"="Geometry-1"}

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			#define PI 3.14159265
			#define TAU (2*PI)
			#define PHI (sqrt(5)*0.5 + 0.5)

			#define MAX_STEPS 100
			#define MAX_STEPS_F float(MAX_STEPS)

			#define FIXED_STEP_SIZE .05

			#define MAX_DISTANCE 50.0
			#define MIN_DISTANCE .5
			#define EPSILON .01
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

			uniform int _SDFShapeCount;
			uniform float4 _SDFShapeParameters[MAX_SHAPE_COUNT];
			uniform float4x4 _SDFShapeTransforms[MAX_SHAPE_COUNT]; 

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

			float sdf_simple(float3 p)
			{
				float d = 1000.0;

				[loop]
				for (int i = 0; i < _SDFShapeCount; ++i)
				{
					float4 params = _SDFShapeParameters[i];
					float3 wsPos = mul(_SDFShapeTransforms[i], float4(p, 1.0)).xyz;

					int type = int(params.w);

					float dd = 0.0;

					if (type == 1)
						dd = wsPos.y;
					else if (type == 2)
						dd = length(wsPos) - .5;
					else if (type == 3)
						dd = fBox(wsPos);
					else if (type == 4)
						dd = fCylinder(wsPos);

					d = min(d, dd);
				}

				return d;
			}

			float3 sdfNormal(float3 p, float epsilon)
			{
				float3 eps = float3(epsilon, -epsilon, 0.0);

				float dX = sdf_simple(p + eps.xzz) - sdf_simple(p + eps.yzz);
				float dY = sdf_simple(p + eps.zxz) - sdf_simple(p + eps.zyz);
				float dZ = sdf_simple(p + eps.zzx) - sdf_simple(p + eps.zzy);

				return normalize(float3(dX, dY, dZ));
			}
			Intersection Raymarch(Camera camera)
			{
				Intersection outData;
				outData.sdf = 0.0;
				outData.materialID = MATERIAL_NONE;
				outData.totalDistance = 0.0;

				for (int j = 0; j < MAX_STEPS; ++j)
				{
					float3 p = camera.origin + camera.direction * outData.totalDistance;
					outData.sdf = sdf_simple(p);
					
					outData.totalDistance += outData.sdf;

					if (outData.sdf < EPSILON)
						break;
				}

				if (outData.sdf < EPSILON)
					outData.materialID = 1;

				return outData;
			}

			float3 Render(Camera camera, Intersection isect, float2 uv)
			{
				float3 p = camera.origin + camera.direction * isect.totalDistance;

				if (isect.materialID > 0)
				{
					float3 normal = sdfNormal(p, EPSILON_NORMAL);
					return dot(normal, -_WorldSpaceLightPos0.xyz) + max(0.0, -dot(normal, -_WorldSpaceLightPos0.xyz));
				}

				return 0.0;
			}

			float4 frag (v2f i) : SV_Target
			{
				Camera camera;
				camera.origin = _WorldSpaceCameraPos;
				camera.direction = normalize(i.worldSpacePosition - camera.origin);

				Intersection isect = Raymarch(camera);
				float3 color = Render(camera, isect, i.uv);

				return float4(pow(color, .45454), 1.0);
			}
			ENDCG
		}
	}
}
