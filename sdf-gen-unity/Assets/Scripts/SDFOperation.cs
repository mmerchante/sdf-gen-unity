using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class SDFOperation : MonoBehaviour
{
    public enum OperationType
    {
        Union = 0,
        Substraction = 1,
        Intersection = 2
    }

    public OperationType operationType = OperationType.Union;
    
    public void Update()
    {
        this.name = operationType.ToString();
    }
}