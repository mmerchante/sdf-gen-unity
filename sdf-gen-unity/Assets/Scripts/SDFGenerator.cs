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
    public bool verboseOutput = false;
    public bool transformArray = false;

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
            }
        }
    }

    private string GetFloatIdentifier()
    {
        return "float";
    }

    private string DeclareVector4ArrayVariable(string var, int size)
    {
        return GetVector4Identifier() + " " + var + "[" + size + "];\n";
    }

    private string DeclareVector3ArrayVariable(string var, int size)
    {
        return GetVector3Identifier() + " " + var + "[" + size + "];\n";
    }

    private string DeclareFloatArrayVariable(string var, int size)
    {
        return GetFloatIdentifier() + " " + var + "[" + size + "];\n";
    }

    private string DeclareConstMatrixArrayVariable(string var, List<Matrix4x4> matrices)
    {
        string output = "const " + GetMatrix4x4Identifier() + " " + var + "[" + matrices.Count + "] = " + GetMatrix4x4Identifier() + "[" + matrices.Count + "](\n";

        for (int i = 0; i < matrices.Count; ++i)
            output += GetTabs(1) + ConstructVariable(matrices[i]) + (i < matrices.Count - 1 ? ",\n" : "\n");

        output += ");\n";
        return output;
    }

    private string DeclareVariable(string var, float value)
    {
        return GetFloatIdentifier() + " " + var + " = " + ConstructVariable(value) +  ";\n";
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

        output += ConstructVariable(m.m00) + ", ";
        output += ConstructVariable(m.m01) + ", ";
        output += ConstructVariable(m.m02) + ", ";
        output += ConstructVariable(m.m03) + ", ";

        output += ConstructVariable(m.m10) + ", ";
        output += ConstructVariable(m.m11) + ", ";
        output += ConstructVariable(m.m12) + ", ";
        output += ConstructVariable(m.m13) + ", ";
        
        output += ConstructVariable(m.m20) + ", ";
        output += ConstructVariable(m.m21) + ", ";
        output += ConstructVariable(m.m22) + ", ";
        output += ConstructVariable(m.m23) + ", ";
        
        output += ConstructVariable(m.m30) + ", ";
        output += ConstructVariable(m.m31) + ", ";
        output += ConstructVariable(m.m32) + ", ";
        output += ConstructVariable(m.m33) + ")";
        
        return output;
    }


    private string ConstructVariable(Vector4 p)
    {
        return GetVector4Identifier() + "(" + ConstructVariable(p.x) + "," + ConstructVariable(p.y) + "," + ConstructVariable(p.z) + "," + ConstructVariable(p.w) + ")";
    }

    private string ConstructVariable(Vector3 p)
    {
        return GetVector3Identifier() + "(" + ConstructVariable(p.x) + "," + ConstructVariable(p.y) + "," + ConstructVariable(p.z) + ")";
    }

    private string ConstructVariable(float f)
    {
        return f.ToString(".0##");
    }

    public void Update()
    {
        if(Input.GetKeyDown(KeyCode.Space))
        {
            Debug.Log("Copied to clipboard");
            GUIUtility.systemCopyBuffer = GenerateCode();
        }
    }

    private string GetTabs(int indent)
    {
        if (!verboseOutput)
            indent = 1;

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
        List<Matrix4x4> matrices = new List<Matrix4x4>();

        for (int i = 0; i < nodes.Length; ++i)
            nodeMap[nodes[i]] = i;

        // The stack is just an easy way to deal with node states
        output += GetTabs(1) + DeclareVariable("wsPos", Vector3.zero);
        output += GetTabs(1) + DeclareFloatArrayVariable("stack", nodes.Length);
        output += GetTabs(1) + DeclareVector4ArrayVariable("pStack", nodes.Length);
        output += GetTabs(1) + "pStack[0] = " + GetVector4Identifier() + "(p, 1.0);\n"; // Initialize root position
        
        output += GenerateCodeForNode(nodeMap, root, 0, matrices);

        output += GetTabs(1) + "return stack[0];\n";
        output += "}\n";

        string matrixArrayDeclaration = DeclareConstMatrixArrayVariable("tr", matrices);

        if (transformArray)
            output = matrixArrayDeclaration + "\n" + output;

        return output;
    }

    private string GetOperationCode(int op, string a, string b)
    {
        if (op == 1)
            return "max(-" + a + "," + b + ")";
        else if (op == 2)
            return "max(" + a + "," + b + ")";

        return "min(" + a + "," + b + ")";
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

    private string GetShapeCode(SDFShape shape, string parentPosition)
    {
        Vector3 offset = shape.transform.localPosition;
        Vector3 up = shape.transform.localRotation * Vector3.up;
        Vector3 right = shape.transform.localRotation * Vector3.right;
        Vector3 forward = shape.transform.localRotation * Vector3.forward;

        switch (shape.shapeType)
        {
            case SDFShape.ShapeType.Plane:
                return "dot("+ parentPosition + " - " + ConstructVariable(offset) + ", " + ConstructVariable(up) + ")";
            case SDFShape.ShapeType.FracturedPlane:
                //return "wsPos.y + (clamp(wsPos.x, 0.0, 2.0) * 0.05 + clamp(wsPos.z + .5, 0.0, 1.0) * .1)";
                return "frPlane(wsPos)";
            case SDFShape.ShapeType.Sphere:
                return "length(wsPos) - .5";
            case SDFShape.ShapeType.Cube:
                return "fBox(wsPos)";
            case SDFShape.ShapeType.Cylinder:
                return "fCylinder(wsPos)";
        }

        return "0.0"; // Worst case
    }

    private string MultiplyMatrixVector4(string m, string p)
    {
        switch (outputLanguage)
        {
            case ShadingLanguage.GLSL:
                return "(" + m + " * " + p + ")";
            case ShadingLanguage.HLSL:
                return "mul(" + m + "," + p + ")";
        }

        return "";
    }
    
    private string MultiplyMatrixVector3(string m, string p)
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

    private string GenerateCodeForNode(Dictionary<SDFOperation, int> nodeMap, GameObject go, int depth, List<Matrix4x4> matrices)
    {
        string output = "";

        SDFOperation op = go.GetComponent<SDFOperation>();

        if (op)
        {
            if(verboseOutput)
                output += GetTabs(depth + 1) + "{\n";

            int stackIndex = nodeMap[op];
            string nodeStackPosition = "pStack[" + stackIndex + "]";

            Matrix4x4 localInverse = Matrix4x4.TRS(op.transform.localPosition, op.transform.localRotation, op.transform.localScale).inverse;

            if (localInverse != Matrix4x4.identity)
            {
                string sourcePosition = nodeStackPosition;

                if (depth > 0)
                {
                    int parentStackIndex = nodeMap[go.transform.parent.gameObject.GetComponent<SDFOperation>()];
                    sourcePosition = "pStack[" + parentStackIndex + "]";
                }

                if (op.transform.localRotation == Quaternion.identity)
                {
                    Vector4 offset = op.transform.localPosition;
                    offset.w = 0f;

                    if (verboseOutput)
                        output += GetTabs(depth + 2) + "// Optimized rotation\n";
                    
                    output += GetTabs(depth + 2) + nodeStackPosition + " = ";

                    if (op.transform.localScale != Vector3.one)
                    {
                        Vector3 scale = op.transform.localScale;
                        Vector4 invScale = new Vector4(1f / scale.x, 1f / scale.y, 1f / scale.z, 1f);                        
                        output += "(" + sourcePosition + " * " + ConstructVariable(invScale) + ")";
                    }
                    else
                    {
                        output += sourcePosition;
                    }

                    if(offset.magnitude > 0f)
                        output += " - " + ConstructVariable(offset) + ";\n";
                    else
                        output += ";\n";
                }
                else
                {
                    // Just use the matrix if there's rotation
                    string matrixVariable = "tr[" + matrices.Count + "]";
                    matrices.Add(localInverse);

                    if (transformArray)
                        output += GetTabs(depth + 2) + nodeStackPosition + " = " + MultiplyMatrixVector4(matrixVariable, sourcePosition) + ";\n";
                    else
                        output += GetTabs(depth + 2) + nodeStackPosition + " = " + MultiplyMatrixVector4(ConstructVariable(localInverse), sourcePosition) + ";\n";
                }
            }
            else
            {
                if(verboseOutput)
                    output += GetTabs(depth + 2) + "// Transform optimized\n";

                if (depth > 0)
                {
                    int parentStackIndex = nodeMap[go.transform.parent.gameObject.GetComponent<SDFOperation>()];
                    output += GetTabs(depth + 2) + nodeStackPosition + " = " + "pStack[" + parentStackIndex + "];\n";
                }
            }

            if(op.distortionType != SDFOperation.DomainDistortion.None)
            {
                switch (op.distortionType)
                {
                    case SDFOperation.DomainDistortion.Repeat3D:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".xyz = domainRepeat(" + nodeStackPosition + ".xyz , " + ConstructVariable(op.domainRepeat) + ");\n";
                        break;
                    case SDFOperation.DomainDistortion.RepeatX:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".x = domainRepeat1D(" + nodeStackPosition + ".x , " + ConstructVariable(op.domainRepeat.x) + ");\n";
                        break;
                    case SDFOperation.DomainDistortion.RepeatY:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".y = domainRepeat1D(" + nodeStackPosition + ".y , " + ConstructVariable(op.domainRepeat.y)+ ");\n";
                        break;                                                                                                                                       
                    case SDFOperation.DomainDistortion.RepeatZ:                                                                                                      
                        output += GetTabs(depth + 2) + nodeStackPosition + ".z = domainRepeat1D(" + nodeStackPosition + ".z , " + ConstructVariable(op.domainRepeat.z)+ ");\n";
                        break;
                    case SDFOperation.DomainDistortion.RepeatPolarX:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".yz = pModPolar(" + nodeStackPosition + ".yz , " + ConstructVariable(op.domainRepeat.x) + ");\n";
                        break;
                    case SDFOperation.DomainDistortion.RepeatPolarY:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".xz = pModPolar(" + nodeStackPosition + ".xz , " + ConstructVariable(op.domainRepeat.x) + ");\n";
                        break;
                    case SDFOperation.DomainDistortion.RepeatPolarZ:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".xy = pModPolar(" + nodeStackPosition + ".xy , " + ConstructVariable(op.domainRepeat.x) + ");\n";
                        break;
                }
            }

            bool first = true;
            bool carryOverFirstOp = false;
            int carryOverOpIndex = -1;

            foreach (Transform child in go.transform)
            {
                GameObject childGO = child.gameObject;

                if (!childGO.activeInHierarchy)
                    continue;

                int currentIndex = stackIndex;

                if (carryOverFirstOp)
                    currentIndex = carryOverOpIndex;

                if (childGO.GetComponent<SDFOperation>())
                {
                    output += GenerateCodeForNode(nodeMap, childGO, depth + 1, matrices);
                    int childStackIndex = nodeMap[childGO.GetComponent<SDFOperation>()];

                    if (first)
                    {
                        carryOverFirstOp = true;
                        carryOverOpIndex = childStackIndex;

                        if(verboseOutput)
                            output += GetTabs(depth + 2) + "// Optimized first operation carry over\n";
                    }
                    else
                    {
                        output += GetTabs(depth + 2) + "stack[" + stackIndex + "] = ";
                        output += GetOperationCode((int)op.operationType, "stack[" + currentIndex + "]", "stack[" + childStackIndex + "]") + ";\n";

                        carryOverFirstOp = false;
                    }
                }
                else if(childGO.GetComponent<SDFShape>())
                {
                    SDFShape shape = childGO.GetComponent<SDFShape>();
                    string shapeCode = GetShapeCode(shape, nodeStackPosition + ".xyz");

                    if (UseTransform(shape))
                    {
                        Matrix4x4 localShapeInverse = Matrix4x4.TRS(shape.transform.localPosition, shape.transform.localRotation, shape.transform.localScale).inverse;
                        string matrixVariable = "tr[" + matrices.Count + "]";
                        matrices.Add(localShapeInverse);

                        if (transformArray)
                            output += GetTabs(depth + 2) + "wsPos = " + MultiplyMatrixVector4(matrixVariable, nodeStackPosition) + ".xyz;\n";
                        else
                            output += GetTabs(depth + 2) + "wsPos = " + MultiplyMatrixVector4(ConstructVariable(localShapeInverse), nodeStackPosition) + ".xyz;\n";
                    }

                    output += GetTabs(depth + 2) + "stack[" + stackIndex + "] = ";
                    
                    if (first)
                        output += shapeCode + ";\n";
                    else
                        output += GetOperationCode((int)op.operationType, "stack[" + currentIndex + "]", shapeCode) + ";\n";

                    carryOverFirstOp = false;
                }
                else
                {
                    Debug.LogError("Something that is not an op or a shape is in the hierarchy! " + childGO.name, childGO);
                }

                first = false;
            }

            // If we're still carrying over, but finished this node... 
            if(carryOverFirstOp)
            {
                if (verboseOutput)
                    output += GetTabs(depth + 2) + "// Carrying over node with single child \n";
                
                output += GetTabs(depth + 2) + "stack[" + stackIndex + "] = stack[" + carryOverOpIndex + "];\n";
            }

            if (verboseOutput)
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
