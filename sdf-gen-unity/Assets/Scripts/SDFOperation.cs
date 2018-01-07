using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SDFOperation : MonoBehaviour
{
    public enum OperationType
    {
        Union = 0,
        Substraction = 1,
        Intersection = 2
    }

    public OperationType operationType = OperationType.Union;

    private List<SDFShape> children = new List<SDFShape>(10);

    public List<SDFShape> GetShapes()
    {
        // No caching
        GetComponentsInChildren<SDFShape>(children);
        return children;
    }
}