using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class SDFGenerator : MonoBehaviour
{
    public MeshRenderer quadRenderer;

    private const int MAX_SHAPES = 128;

    private Material material;
    private Vector4[] data = new Vector4[MAX_SHAPES];
    private Matrix4x4[] transforms = new Matrix4x4[MAX_SHAPES];

    public void Awake()
    {
        this.material = quadRenderer.sharedMaterial;
    }

    public void LateUpdate()
    {
        SDFShape[] shapes = GetComponentsInChildren<SDFShape>();
        int count = Mathf.Min(MAX_SHAPES, shapes.Length);

        for (int i = 0; i < count; ++i)
        {
            data[i] = shapes[i].GetParameters();
            transforms[i] = shapes[i].transform.worldToLocalMatrix;
        }

        if (data.Length > 0)
        {
            material.SetVectorArray("_SDFShapeParameters", data);
            material.SetMatrixArray("_SDFShapeTransforms", transforms);
        }

        material.SetInt("_SDFShapeCount", count);
    }
}
