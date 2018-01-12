using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

public enum ShadingLanguage
{
    GLSL,
    HLSL,
}

[ExecuteInEditMode]
public class SDFGenerator : MonoBehaviour
{
    private const int MAX_SHAPES = 128; 

    public ShadingLanguage outputLanguage = ShadingLanguage.HLSL;
    public MeshRenderer quadRenderer;
    public GameObject root;

    private Material material;
    private ComputeBuffer nodeBuffer;
    private RenderTexture accumulationBuffer;

    private Matrix4x4 camTransform;

    public struct Node
    {
        public Matrix4x4 transform;
        public int type;
        public int parameters;
        public int depth;
        public int domainDistortionType;
        public Vector3 domainDistortion;
    }

    public void Awake()
    {
        this.material = quadRenderer.sharedMaterial;

        // Bypass frustum culling
        Mesh m = quadRenderer.GetComponent<MeshFilter>().sharedMesh;
        m.bounds = new Bounds(Vector3.zero, Vector3.one * 1000f);
    }

    private void RebuildSceneData()
    {
        List<Node> tree = new List<Node>();
        BuildNodeTree(this.gameObject, tree, 0);

        if (nodeBuffer == null)
        {
            int nodeSize = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Node));
            this.nodeBuffer = new ComputeBuffer(MAX_SHAPES, nodeSize, ComputeBufferType.Default);
        }

        this.nodeBuffer.SetData(tree.ToArray());

        material.SetBuffer("_SceneTree", this.nodeBuffer);
        material.SetInt("_SDFShapeCount", tree.Count);
    }

    public void OnDestroy()
    {
        if (nodeBuffer != null)
            nodeBuffer.Release();
    }

    private void RebuildAccumulationBuffer(bool force)
    {
        Camera cam = Camera.current;

        if (cam)
        {
            int pixels = (int)(cam.pixelRect.width * cam.pixelRect.height);

            if (force || camTransform != cam.transform.localToWorldMatrix || accumulationBuffer == null || accumulationBuffer.width * accumulationBuffer.height != pixels)
            {
                if (accumulationBuffer != null)
                {
                    accumulationBuffer.Release();
                }

                accumulationBuffer = new RenderTexture((int)cam.pixelRect.width, (int)cam.pixelRect.height, 0, RenderTextureFormat.RFloat);
                accumulationBuffer.useMipMap = false;
                accumulationBuffer.autoGenerateMips = false;
                accumulationBuffer.enableRandomWrite = true;
                accumulationBuffer.Create();

                material.SetTexture("_AccumulationBuffer", accumulationBuffer);

                camTransform = cam.transform.localToWorldMatrix;

                if (accumulationBuffer)
                {
                    Graphics.SetRandomWriteTarget(1, accumulationBuffer);
                    //Graphics.SetRenderTarget(null);
                    //Graphics.ClearRandomWriteTargets();
                }

                Debug.Log("Updating...");
            }
        }
    }

    private string GetFloatIdentifier()
    {
        return "float";
    }

    private string DeclareFloatArrayVariable(string var, int size)
    {
        return GetFloatIdentifier() + " " + var + "[" + size + "];\n";
    }

    private string DeclareVariable(string var, float value)
    {
        return GetFloatIdentifier() + " " + var + " = " + value.ToString(".0#####") + ";\n";
    }

    private string GetMatrix4x4Identifier()
    {
        switch (outputLanguage)
        {
            case ShadingLanguage.GLSL:
                return "mat4";
            case ShadingLanguage.HLSL:
                return "float4x4";
        }

        return "";
    }

    private string GetVector4Identifier()
    {
        switch (outputLanguage)
        {
            case ShadingLanguage.GLSL:
                return "vec4";
            case ShadingLanguage.HLSL:
                return "float4";
        }

        return "";
    }

    private string GetVector3Identifier()
    {
        switch (outputLanguage)
        {
            case ShadingLanguage.GLSL:
                return "vec3";
            case ShadingLanguage.HLSL:
                return "float3";
        }

        return "";
    }

    private string DeclareVariable(string var, Vector3 p)
    {
        return GetVector3Identifier() + " " + var + " = " + ConstructVariable(p) + ";\n";
    }

    private string DeclareVariable(string var, Matrix4x4 m)
    {
        return GetMatrix4x4Identifier() + " " + var + " = " + ConstructVariable(m) + ";\n";
    }

    private string ConstructVariable(Matrix4x4 m)
    {
        string output = GetMatrix4x4Identifier() + "(";

        if(outputLanguage == ShadingLanguage.GLSL)
            m = m.transpose;

        output += m.m00.ToString(".0#####") + ", ";
        output += m.m01.ToString(".0#####") + ", ";
        output += m.m02.ToString(".0#####") + ", ";
        output += m.m03.ToString(".0#####") + ", ";

        output += m.m10.ToString(".0#####") + ", ";
        output += m.m11.ToString(".0#####") + ", ";
        output += m.m12.ToString(".0#####") + ", ";
        output += m.m13.ToString(".0#####") + ", ";

        output += m.m20.ToString(".0#####") + ", ";
        output += m.m21.ToString(".0#####") + ", ";
        output += m.m22.ToString(".0#####") + ", ";
        output += m.m23.ToString(".0#####") + ", ";

        output += m.m30.ToString(".0#####") + ", ";
        output += m.m31.ToString(".0#####") + ", ";
        output += m.m32.ToString(".0#####") + ", ";
        output += m.m33.ToString(".0#####") + ")";
        
        return output;
    }

    private string ConstructVariable(Vector3 p)
    {
        return GetVector3Identifier() + "(" + p.x.ToString(".0#####") + "," + p.y.ToString(".0#####") + "," + p.z.ToString(".0#####") + ")";
    }

    public void Update()
    {
        if(Input.GetKeyDown(KeyCode.Space))
            Debug.Log(GenerateCode());
    }

    private string GetTabs(int indent)
    {
        string output = "";

        while (indent-- > 0)
            output += '\t';

        return output;
    }

    private string Newline()
    {
        return "\n";
    }

    // Please note: this code is absolutely hacky and in no way designed for a scalable code 
    // generator. But it gets the job done quickly ;)
    public string GenerateCode()
    {
        // StringBuilder? What is that?
        string output = "float sdf_generated(" + GetVector3Identifier() + " p)\n{\n";

        Dictionary<SDFOperation, int> nodeMap = new Dictionary<SDFOperation, int>();
        SDFOperation[] nodes = gameObject.GetComponentsInChildren<SDFOperation>();

        for (int i = 0; i < nodes.Length; ++i)
            nodeMap[nodes[i]] = i;

        // The stack is just an easy way to deal with node states
        output += GetTabs(1) + DeclareFloatArrayVariable("stack", nodes.Length);
        output += GetTabs(1) + DeclareVariable("wsPos", Vector3.zero);

        output += GenerateCodeForNode(nodeMap, root, 0);

        output += GetTabs(1) + "return stack[0];\n";
        output += "}\n";
        return output;
    }

    private string GetOperationCode(int op, string a, string b)
    {
        if (op == 1)
            return "max(-" + a + "," + b + ")";
        else if (op == 2)
            return "max(" + a + "," + b + ")";

        return "min( " + a + "," + b + ")";
    }

    private bool UseTransform(SDFShape shape)
    {
        switch (shape.shapeType)
        {
            case SDFShape.ShapeType.Plane:
                return false;
            default:
                return true;
        }
    }

    private string GetShapeCode(SDFShape shape)
    {
        switch (shape.shapeType)
        {
            case SDFShape.ShapeType.Plane:
                Vector3 offset = shape.transform.position;
                Vector3 up = shape.transform.up;
                return "dot(p - " + ConstructVariable(offset) + ", " + ConstructVariable(up) + ")";
            case SDFShape.ShapeType.Sphere:
                return "length(wsPos) - .5";
            case SDFShape.ShapeType.Cube:
                return "fBox(wsPos)";
            case SDFShape.ShapeType.Cylinder:
                return "fCylinder(wsPos)";
        }

        return "0.0"; // Worst case
    }

    private string MultiplyMatrixVector(string m, string p)
    {
        switch (outputLanguage)
        {
            case ShadingLanguage.GLSL:
                return "(" + m + " * " + GetVector4Identifier() + "(" + p + ", 1.0)).xyz";
            case ShadingLanguage.HLSL:
                return "mul(" + m + "," + GetVector4Identifier() + "(" + p + ", 1.0)).xyz";
        }

        return "";
    }

    private string GenerateCodeForNode(Dictionary<SDFOperation, int> nodeMap, GameObject go, int depth)
    {
        string output = "";

        SDFOperation op = go.GetComponent<SDFOperation>();

        if (op)
        {
            output += GetTabs(depth + 1) + "{\n";

            int stackIndex = nodeMap[op];
            bool first = true;

            foreach (Transform child in go.transform)
            {
                GameObject childGO = child.gameObject;
                                
                if (childGO.GetComponent<SDFOperation>())
                {
                    output += GenerateCodeForNode(nodeMap, childGO, depth + 1);
                    int childStackIndex = nodeMap[childGO.GetComponent<SDFOperation>()];

                    output += GetTabs(depth + 2) + "stack[" + stackIndex + "] = ";

                    if (first)
                        output += "stack[" + childStackIndex + "];\n";
                    else
                        output += GetOperationCode((int)op.operationType, "stack[" + stackIndex + "]", "stack[" + childStackIndex + "]") + ";\n";
                }
                else if(childGO.GetComponent<SDFShape>())
                {
                    SDFShape shape = childGO.GetComponent<SDFShape>();
                    string shapeCode = GetShapeCode(shape);

                    if (UseTransform(shape))
                        output += GetTabs(depth + 2) + "wsPos = " + MultiplyMatrixVector(ConstructVariable(shape.transform.worldToLocalMatrix), "p") + ";\n";
                    else
                        output += GetTabs(depth + 2) + "wsPos = p;\n";

                    output += GetTabs(depth + 2) + "stack[" + stackIndex + "] = ";

                    if (first)
                        output += shapeCode + ";\n";
                    else
                        output += GetOperationCode((int)op.operationType, "stack[" + stackIndex + "]", shapeCode) + ";\n";
                }
                else
                {
                    Debug.LogError("Something that is not an op or a shape is in the hierarchy! " + childGO.name, childGO);
                }

                first = false;
            }

            output += GetTabs(depth + 1) + "}\n";
        }

        return output;
    }

    private void BuildNodeTree(GameObject go, List<Node> nodeList, int depth)
    {
        if (!go.activeInHierarchy)
            return;

        SDFOperation op = go.GetComponent<SDFOperation>();
        SDFShape shape = go.GetComponent<SDFShape>();

        Node node = new Node();
        node.transform = Matrix4x4.TRS(go.transform.localPosition, go.transform.localRotation, go.transform.localScale).inverse;
        node.type = 0;
        node.depth = depth;
        node.domainDistortionType = 0;
        node.domainDistortion = Vector3.one;

        if (op)
        {
            node.type = 0;
            node.parameters = (int)op.operationType;
            node.domainDistortionType = (int)op.distortionType;
            node.domainDistortion = op.domainRepeat; // For now...
        }
        else if (shape)
        {
            node.type = 1;
            node.parameters = (int)shape.shapeType;
        }

        nodeList.Add(node);

        foreach(Transform child in go.transform)
            BuildNodeTree(child.gameObject, nodeList, depth+1);
    }

    public void LateUpdate()
    {
        RebuildSceneData();
    }

    public void UpdateRaymarcher(bool force)
    {
        RebuildAccumulationBuffer(force);
    }
}
