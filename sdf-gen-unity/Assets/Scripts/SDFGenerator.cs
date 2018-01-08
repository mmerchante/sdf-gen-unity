using System.Collections;
using System.Collections.Generic;
using UnityEngine;


[ExecuteInEditMode]
public class SDFGenerator : MonoBehaviour
{
    private const int MAX_SHAPES = 128;

    public MeshRenderer quadRenderer;

    private Material material;
    private ComputeBuffer nodeBuffer;

    public struct Node
    {
        public Matrix4x4 transform;
        public int type;
        public int parameters;
        public int depth;
    }

    public void Awake()
    {
        this.material = quadRenderer.sharedMaterial;
    }

    private void RebuildSceneData()
    {
        SDFShape[] shapes = GetComponentsInChildren<SDFShape>();
        int count = Mathf.Min(MAX_SHAPES, shapes.Length);

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
        if(nodeBuffer != null)
            nodeBuffer.Release();
    }

    private void BuildNodeTree(GameObject go, List<Node> nodeList, int depth)
    {
        SDFOperation op = go.GetComponent<SDFOperation>();
        SDFShape shape = go.GetComponent<SDFShape>();

        Node node = new Node();
        node.transform = Matrix4x4.TRS(go.transform.localPosition, go.transform.localRotation, go.transform.localScale).inverse;
        node.type = 0;
        node.depth = depth;

        if (op)
        {
            node.type = 0;
            node.parameters = (int)op.operationType;
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
}
