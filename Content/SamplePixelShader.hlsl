cbuffer ModelViewProjectionConstantBuffer : register(b0)
{
	matrix model;
	matrix view;
	matrix projection;
	float2 screenSize;
	float iTime;
};

// Per-pixel color data passed through the pixel shader.
struct PixelShaderInput
{
	float4 pos : SV_POSITION;
	float2 uv : TEXCOORD0;
};

float2 rotate(float2 pos, float angle)
{
	float c = cos(angle);
	float s = sin(angle);
	
	//float2x2 mat = { c, s, -s, c };
	float2x2 mat = { c, -s, s, c };
	return mul(pos, mat);
}

float plane(float3 pos)
{
	return pos.y;
}

float sphere(float3 pos, float radius)
{
	return length(pos) - radius;
}

float box(float3 pos, float3 size)
{
	return length(max(abs(pos) - size, 0.0f));
}

float roundedBox(float3 pos, float3 size, float radius)
{
	return length(max(abs(pos) - size, 0.0f)) - radius;
}

float map(float3 pos)
{
	float planeDistance = plane(pos);

	pos.xy = rotate(pos.xy, pos.z * sin(iTime) * 0.01f);

	pos = abs(pos);

	pos = fmod(pos + 10.0f, 20.0f) - 10.0f;

	pos.xy = rotate(pos.xy, iTime);
	pos.xz = rotate(pos.xz, iTime * 0.7);

	//if (iMouse.z > 0.0)
	//	return min(planeDistance, roundedBox(pos, float3(2.0f, 2.0f, 2.0f), 1.0f));
	//else
		return min(planeDistance, sphere(pos, 3.0f));
}



float3 computeNormal(float3 pos)
{
	float2 eps = float2(0.01f, 0.0f);
	return normalize(float3(
		map(pos + eps.xyy) - map(pos - eps.xyy),
		map(pos + eps.yxy) - map(pos - eps.yxy),
		map(pos + eps.yyx) - map(pos - eps.yyx)));

}

float diffuse(float3 normal, float3 lightDirection)
{
	// return max(dot(normal, lightDirection), 0.0);
	// wrap lighting
	return dot(normal, lightDirection) * 0.5f + 0.5f;
}

float3 material(float3 pos)
{
	float m = smoothstep(0.4f, 0.41f, frac(pos.x + sin(pos.z * 0.4f + iTime)));
	return float3(m,m,m);

}

float specular(float3 normal, float3 dir)
{
	// IBL
	float3 h = normalize(normal - dir);
	return pow(max(dot(h, normal), 0.0), 100.0);
}

// A pass-through function for the (interpolated) color data.
float4 main(PixelShaderInput input) : SV_TARGET
{
	//BlackNight SDF DX12
	float2 uv = input.uv;

	float ratio = screenSize.x / screenSize.y;
	uv.y /= ratio;

	float3 pos = float3(sin(iTime * 0.2f) * 4.0f, 5.0f + sin(iTime * 0.4f) * 3.0f, -13.0f);
	//float3 pos = float3(1.0f, 1.0f, -13.0f);
	float3 dir = normalize(float3(uv, 1.0f));

	// Ray March 
	for (int i = 0; i < 64; i++)
	{
		float d = map(pos);
		pos += d * dir;
	}

	float3 normal = computeNormal(pos);

	float3 lightPos = float3(0.0, 100.0, -100.0);
	float3 dirToLight = normalize(lightPos - pos);
	float3 posToLight = pos + (0.00001 * dirToLight);

	float fShadowBias = 0.05;
	float fStartDistance = fShadowBias / abs(dot(dirToLight, normal));
	float fLightDistance = 100.0;
	float fLength = fLightDistance - fStartDistance;

	float posToLightDistance = 0.0;
	for (int i = 0; i < 64; i++)
	{
		float d = map(posToLight);
		posToLightDistance += d;
		posToLight += d * dirToLight;
	}

	float fShadow = step(0.0, posToLightDistance) * step(fLightDistance, posToLightDistance);

	float fAmbientOcclusion = 1.0;

	float fDist = 0.0;
	for (int i = 0; i <= 5; i++)
	{
		fDist += 0.1;

		float d = map(pos + normal * fDist);

		fAmbientOcclusion *= 1.0 - max(0.0, (fDist - d) * 0.2 / fDist);
	}

	// get colour from reflected ray
	float fSeparation = 0.1;
	fLength = 160.0;

	float3 dirReflected = reflect(dir, normal);
	fStartDistance = fSeparation / abs(dot(dirReflected, normal));

	float3 posReflected = pos + (0.00001 * dirReflected);

	float posReflectedDistance = 0.0;
	for (int i = 0; i < 64; i++)
	{
		float d = map(posReflected);
		posReflectedDistance += d;
		posReflected += d * dirReflected;
	}

	float fReflected = step(0.0, posReflectedDistance) * step(fLength, posReflectedDistance);

	float diffReflected = diffuse(normal, dirReflected);
	float specReflected = specular(normal, dir);

	float3 colorReflected = (diffReflected + specReflected) * float3(0.0, 0.2, 0.81) * (1.0 - fReflected) * material(posReflected);

	float diff = diffuse(normal, dirToLight);
	float spec = specular(normal, dir);
	float3 color = (diff + spec) * float3(0.0, 0.2, 0.81) *  material(pos);

	float fogFactor = exp(-pos.z * 0.01);
	float3 fogColor = float3(0.0, 0.2, 0.81);

	color = lerp(clamp(color + colorReflected, 0.0, 1.0), clamp(color + colorReflected, 0.0, 1.0) * 0.25, 1.0 - fShadow);
	color = lerp(fogColor, fAmbientOcclusion * color, fogFactor);
		
	return float4(color, 1.0f);


}
