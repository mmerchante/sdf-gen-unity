﻿using System.Collections;
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

    public bool useStack = false;

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
        public float bias;
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

                accumulationBuffer = new RenderTexture((int)cam.pixelRect.width, (int)cam.pixelRect.height, 0, RenderTextureFormat.ARGBFloat);
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

    private string DeclareConstVector3ArrayVariable(string var, List<Vector3> vectors)
    {
        string output = "const " + GetVector3Identifier() + " " + var + "[" + vectors.Count + "] = " + GetVector3Identifier() + "[" + vectors.Count + "](\n";

        for (int i = 0; i < vectors.Count; ++i)
            output += GetTabs(1) + ConstructVariable(vectors[i]) + (i < vectors.Count - 1 ? ",\n" : "\n");

        output += ");\n";
        return output;
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

    private string GetVector2Identifier()
    {
        switch (outputLanguage)
        {
            case ShadingLanguage.GLSL:
                return "vec2";
            case ShadingLanguage.HLSL:
                return "float2";
        }

        return "";
    }

    private string DeclareVariable(string var, Vector4 p)
    {
        return GetVector4Identifier() + " " + var + " = " + ConstructVariable(p) + ";\n";
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

    private string ConstructVariable(Vector2 p)
    {
        return GetVector2Identifier() + "(" + ConstructVariable(p.x) + "," + ConstructVariable(p.y) + ")";
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

    private string GetStackDistanceVariableName(int index, bool declare = false)
    {
          if(useStack)
            return "stack[" + index + "]";

        if(declare)
            return GetFloatIdentifier() + " d" + index;
        
        return "d" + index;
    }

    private string GetStackPositionVariableName(int index, bool declare = false)
    {
        if(useStack)
            return "pStack[" + index + "]";

        if(declare)
            return GetVector4Identifier() + " a" + index;
        
        return "a" + index;
    }

    // Please note: this code is absolutely hacky and in no way designed for a scalable code 
    // generator. But it gets the job done quickly ;)
    public string GenerateCode()
    {
        // StringBuilder? What is that?
        string output = "float sdf_generated(" + GetVector3Identifier() + " p)\n{\n";

        Dictionary<SDFOperation, int> nodeMap = new Dictionary<SDFOperation, int>();
        Dictionary<int, bool> visitMap = new Dictionary<int, bool>();
        Dictionary<int, bool> dVisitMap = new Dictionary<int, bool>();
        SDFOperation[] nodes = gameObject.GetComponentsInChildren<SDFOperation>();
        List<Matrix4x4> matrices = new List<Matrix4x4>();

        for (int i = 0; i < nodes.Length; ++i)
            nodeMap[nodes[i]] = i;

        // The stack is just an easy way to deal with node states
        output += GetTabs(1) + DeclareVariable("wsPos", Vector3.zero);

        if(useStack)
        {
            output += GetTabs(1) + DeclareFloatArrayVariable("stack", nodes.Length);
            output += GetTabs(1) + DeclareVector4ArrayVariable("pStack", nodes.Length);
        }
        
        output += GetTabs(1) + GetStackPositionVariableName(0, true) + " = " + GetVector4Identifier() + "(p, 1.0);\n"; // Initialize root position
        
        output += GenerateCodeForNode(visitMap, dVisitMap, nodeMap, root, 0, matrices);

        output += GetTabs(1) + "return " + GetStackDistanceVariableName(0) + ";\n";
        output += "}\n";

        string matrixArrayDeclaration = DeclareConstMatrixArrayVariable("tr", matrices);

        if (transformArray)
            output = matrixArrayDeclaration + "\n" + output;

        output = DeclareGenerateGDFVectorsArray() + "\n" + output;

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

    private Vector3 GetShapeLocalScale(SDFShape shape)
    {
        if(shape.shapeType == SDFShape.ShapeType.Cube || 
            shape.shapeType == SDFShape.ShapeType.Cylinder)
            return Vector3.one;

        return shape.transform.localScale;
    }

    private Matrix4x4 GetLocalTransform(SDFShape shape)
    {
        return Matrix4x4.TRS(shape.transform.localPosition, shape.transform.localRotation, GetShapeLocalScale(shape));
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
        // Vector3 right = shape.transform.localRotation * Vector3.right;
        // Vector3 forward = shape.transform.localRotation * Vector3.forward;

        Vector3 parameters = shape.GetParameters();

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
                return "fBox(wsPos," + ConstructVariable(shape.GetParameters()) + ")";
            case SDFShape.ShapeType.Cylinder:
                return "fCylinder(wsPos, " + ConstructVariable(parameters.x) + "," + ConstructVariable(parameters.y) + ")";
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

    private string GenerateCodeForNode(Dictionary<int, bool> visitMap, Dictionary<int, bool> dVisitMap, Dictionary<SDFOperation, int> nodeMap, GameObject go, int depth, List<Matrix4x4> matrices)
    {
        string output = "";

        SDFOperation op = go.GetComponent<SDFOperation>();

        if (op)
        {
            if(verboseOutput)
                output += GetTabs(depth + 1) + "{\n";

            int stackIndex = nodeMap[op];
            bool firstTime = !visitMap.ContainsKey(stackIndex);
            string nodeStackPosition = GetStackPositionVariableName(stackIndex, firstTime);
            visitMap[stackIndex] = true;

            float defaultDistance = op.operationType == SDFOperation.OperationType.Intersection ? 1000f : 0f;

            // stack[stackTop].sdf = node.parameters == 2 ? 0.0 : 1000.0; // Make sure we initialize knowing the operation
            // output += GetTabs(depth + 2) + GetStackDistanceVariableName(stackIndex, true) + " = " + defaultDistance.ToString("0.00") + ";\n";

            Matrix4x4 localInverse = Matrix4x4.TRS(op.transform.localPosition, op.transform.localRotation, op.transform.localScale).inverse;

            if (localInverse != Matrix4x4.identity)
            {
                string sourcePosition = nodeStackPosition;

                if (depth > 0)
                {
                    int parentStackIndex = nodeMap[go.transform.parent.gameObject.GetComponent<SDFOperation>()];
                    sourcePosition = GetStackPositionVariableName(parentStackIndex);
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
                    output += GetTabs(depth + 2) + nodeStackPosition + " = " + GetStackPositionVariableName(parentStackIndex) + ";\n";
                }
            }

            nodeStackPosition = GetStackPositionVariableName(stackIndex);

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
                    case SDFOperation.DomainDistortion.MirrorXYZ:
                        output += GetTabs(depth + 2) + nodeStackPosition + " = abs(" + nodeStackPosition + ");\n";
                        break;                        
                    case SDFOperation.DomainDistortion.MirrorXZ:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".xz = abs(" + nodeStackPosition + ".xz) * " + ConstructVariable(new Vector2(-1f, 1f)) + ";\n";
                        break;
                    case SDFOperation.DomainDistortion.MirrorX:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".x = abs(" + nodeStackPosition + ".x);\n";
                        break;                        
                    case SDFOperation.DomainDistortion.MirrorY:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".y = abs(" + nodeStackPosition + ".y);\n";
                        break;                        
                    case SDFOperation.DomainDistortion.MirrorZ:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".z = abs(" + nodeStackPosition + ".z);\n";
                        break;                        
                    case SDFOperation.DomainDistortion.RotateDiscreteX:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".xyz = rdX(" + nodeStackPosition + ".xyz);\n";
                        break;
                    case SDFOperation.DomainDistortion.RotateDiscreteY:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".xyz = rdY(" + nodeStackPosition + ".xyz);\n";
                        break;
                    case SDFOperation.DomainDistortion.RotateDiscreteZ:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".xyz = rdZ(" + nodeStackPosition + ".xyz);\n";
                        break;                        
                    case SDFOperation.DomainDistortion.FlipX:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".x = -" + nodeStackPosition + ".x;\n";
                        break;                        
                    case SDFOperation.DomainDistortion.FlipY:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".y = -" + nodeStackPosition + ".y;\n";
                        break;                        
                    case SDFOperation.DomainDistortion.FlipZ:
                        output += GetTabs(depth + 2) + nodeStackPosition + ".z = -" + nodeStackPosition + ".z;\n";
                        break;
                }
            } 

            bool first = true;
            bool carryOverFirstOp = false;
            int carryOverOpIndex = -1;
            bool distanceEstablished = false;

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
                    output += GenerateCodeForNode(visitMap, dVisitMap, nodeMap, childGO, depth + 1, matrices);
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
                        output += GetTabs(depth + 2) + GetStackDistanceVariableName(stackIndex, !distanceEstablished) + " = ";
                        output += GetOperationCode((int)op.operationType, GetStackDistanceVariableName(currentIndex), GetStackDistanceVariableName(childStackIndex)) + ";\n";

                        carryOverFirstOp = false;
                        distanceEstablished = true;
                    }
                }
                else if(childGO.GetComponent<SDFShape>())
                {
                    SDFShape shape = childGO.GetComponent<SDFShape>();
                    string shapeCode = GetShapeCode(shape, nodeStackPosition + ".xyz");

                    if(shape.sdfBias != 1f)
                        shapeCode = "(" + shapeCode + "*" + ConstructVariable(shape.sdfBias) + ")";

                    if (UseTransform(shape))
                    {
                        Matrix4x4 localShapeTransform = GetLocalTransform(shape);

                        if(localShapeTransform == Matrix4x4.identity)
                        {
                            if(verboseOutput)
                                output += GetTabs(depth + 2) + "// Shape transform optimized\n";

                            output += GetTabs(depth + 2) + "wsPos = " + nodeStackPosition + ".xyz;\n";
                        }
                        else
                        {
                            if(shape.transform.localRotation == Quaternion.identity)
                            {
                                Vector3 offset = shape.transform.localPosition;

                                if (verboseOutput)
                                    output += GetTabs(depth + 2) + "// Shape optimized rotation\n";

                                output += GetTabs(depth + 2) + "wsPos = ";

                                Vector3 scale = GetShapeLocalScale(shape);
                                if (scale != Vector3.one)
                                {
                                    Vector3 invScale = new Vector3(1f / scale.x, 1f / scale.y, 1f / scale.z);
                                    output += "( " + nodeStackPosition + ".xyz * " + ConstructVariable(invScale) + ")";
                                }
                                else
                                {
                                    output += nodeStackPosition + ".xyz";
                                }

                                if(offset.magnitude > 0f)
                                    output += " - " + ConstructVariable(offset) + ";\n";
                                else
                                    output += ";\n";
                            }
                            else
                            {
                                Matrix4x4 localShapeInverse = localShapeTransform.inverse;
                                string matrixVariable = "tr[" + matrices.Count + "]";
                                matrices.Add(localShapeInverse);

                                if (transformArray)
                                    output += GetTabs(depth + 2) + "wsPos = " + MultiplyMatrixVector4(matrixVariable, nodeStackPosition) + ".xyz;\n";
                                else
                                    output += GetTabs(depth + 2) + "wsPos = " + MultiplyMatrixVector4(ConstructVariable(localShapeInverse), nodeStackPosition) + ".xyz;\n";
                            }                            
                        }

                    }

                    output += GetTabs(depth + 2) + GetStackDistanceVariableName(stackIndex, !distanceEstablished) + " = ";
                    distanceEstablished = true;
                    
                    if (first)
                        output += shapeCode + ";\n";
                    else
                        output += GetOperationCode((int)op.operationType, GetStackDistanceVariableName(currentIndex), shapeCode) + ";\n";

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
                
                output += GetTabs(depth + 2) + GetStackDistanceVariableName(stackIndex, true) + " = " + GetStackDistanceVariableName(carryOverOpIndex) + ";\n";
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

        Vector3 scale = go.transform.localScale;

        if(shape)
            scale = GetShapeLocalScale(shape);

        Node node = new Node();
        node.transform = Matrix4x4.TRS(go.transform.localPosition, go.transform.localRotation, scale).inverse;
        node.type = 0;
        node.depth = depth;
        node.domainDistortionType = 0;
        node.domainDistortion = Vector3.one;
        node.bias = 1f;

        if (op)
        {
            node.type = 0;
            node.parameters = (int)op.operationType;
            node.domainDistortionType = (int)op.distortionType;
            node.domainDistortion = op.domainRepeat; // For now...
            node.bias = 1f;
        }
        else if (shape)
        {
            node.type = 1;
            node.parameters = (int)shape.shapeType;
            node.domainDistortion = shape.GetParameters();
            node.bias = shape.sdfBias;
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

    public string DeclareGenerateGDFVectorsArray()
    {
        float phi = Mathf.Sqrt(5f) * .5f + .5f;
        List<Vector3> planes = new List<Vector3>();
        
        planes.Add(new Vector3(1, 0, 0));
        planes.Add(new Vector3(0, 1, 0));
        planes.Add(new Vector3(0, 0, 1));

        planes.Add(new Vector3(1, 1, 1));
        planes.Add(new Vector3(-1, 1, 1));
        planes.Add(new Vector3(1, -1, 1));
        planes.Add(new Vector3(1, 1, -1));

        planes.Add(new Vector3(0, 1, phi + 1));
        planes.Add(new Vector3(0, -1, phi + 1));
        planes.Add(new Vector3(phi + 1, 0, 1));
        planes.Add(new Vector3(-phi - 1, 0, 1));
        planes.Add(new Vector3(1, phi + 1, 0));
        planes.Add(new Vector3(-1, phi + 1, 0));

        planes.Add(new Vector3(0, phi, 1));
        planes.Add(new Vector3(0, -phi, 1));
        planes.Add(new Vector3(1, 0, phi));
        planes.Add(new Vector3(-1, 0, phi));
        planes.Add(new Vector3(phi, 1, 0));
        planes.Add(new Vector3(-phi, 1, 0));

        for (int i = 0; i < planes.Count; i++)
            planes[i] = planes[i].normalized;
        
        return DeclareConstVector3ArrayVariable("GDFVectors", planes);
    }
}
