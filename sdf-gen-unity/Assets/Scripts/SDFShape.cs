using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
[RequireComponent(typeof(MeshRenderer))]
[RequireComponent(typeof(MeshFilter))]
public class SDFShape : MonoBehaviour
{
    public enum ShapeType
    {
        None = 0,
        Plane = 1,
        Sphere = 2,
        Cube = 3,
        Cylinder = 4,
        Mesh = 5,
        FracturedPlane = 6,
    }

    public ShapeType shapeType = ShapeType.Sphere;

    public float sdfBias = 1f;

    private MeshFilter filter;
    private MeshRenderer meshRenderer;
    private ShapeType prevType = ShapeType.Sphere;

    private void Awake()
    {
        this.meshRenderer = GetComponent<MeshRenderer>();
        this.filter = GetComponent<MeshFilter>();
        this.prevType = shapeType;

        this.meshRenderer.sharedMaterial = new Material(Shader.Find("Particles/Alpha Blended"));
        this.meshRenderer.sharedMaterial.SetColor("_TintColor", new Color(0f, 0f, 0f, 0f));

        RebuildMesh();
    }

    protected void Update()
    {
        if (prevType != shapeType)
            RebuildMesh();

        this.name = shapeType.ToString();
        prevType = shapeType;
    }

    private void RebuildMesh()
    {
        PrimitiveType t = PrimitiveType.Sphere;

        switch (shapeType)
        {
            case ShapeType.None:
                break;
            case ShapeType.Plane:
            case ShapeType.FracturedPlane:
                t = PrimitiveType.Plane;
                break;
            case ShapeType.Sphere:
                t = PrimitiveType.Sphere;
                break;
            case ShapeType.Cube:
                t = PrimitiveType.Cube;
                break;
            case ShapeType.Cylinder:
                t = PrimitiveType.Cylinder;
                break;
            case ShapeType.Mesh:
                break;
        }

        GameObject go = GameObject.CreatePrimitive(t);
        this.filter.sharedMesh = go.GetComponent<MeshFilter>().sharedMesh;
        GameObject.DestroyImmediate(go);
    }

    public Vector3 GetParameters()
    {
        float type = ((int)shapeType);

        switch (shapeType)
        {
            case ShapeType.None:
                break;
            case ShapeType.Plane:
            case ShapeType.FracturedPlane:
                return new Vector3(transform.up.x, transform.up.y, transform.up.z);
            case ShapeType.Sphere:
                return Vector3.one * type;
            case ShapeType.Cube:
                return new Vector3(transform.localScale.x, transform.localScale.y, transform.localScale.z) * .5f;
            case ShapeType.Cylinder:
                return new Vector3(transform.localScale.x * .5f, transform.localScale.y, 1f);
            case ShapeType.Mesh:
                break;
        }

        return Vector3.zero;
    }
}