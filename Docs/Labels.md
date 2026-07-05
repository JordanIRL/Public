# Labels

# 1. Requirements

* Excel desktop (.xlsm)
* b-PAC SDK installed
* Brother printer + driver installed
* Label template file (.lbx) created in P-touch Editor

***

## 2. Excel Setup

Create columns in row 1:

IMEI | Serial | Asset Tag

Enter data starting from row 2

***

## 3. Create Label Template (.lbx)

Open P-touch Editor:

1. Create a new label
2. Add text/barcode objects
3. Set object names EXACTLY:
   &#x20;  IMEI
   &#x20;  Serial
   &#x20;  Asset Tag
4. Save file (e.g. C:\labels\small.lbx)

***

## 4. Enable VBA in Excel

1. Open Excel file
2. Save as: Excel Macro-Enabled Workbook (.xlsm)
3. Press ALT + F11 to open VBA editor
4. Insert → Module

***

## 5. Paste VBA Code

```vb
Function SetField(doc As Object, fieldName As String, value As String)
    If Not doc.GetObject(fieldName) Is Nothing Then
        doc.GetObject(fieldName).Text = value
    End If
End Function

Sub PrintLabel(templatePath As String)

    Dim doc As Object
    Set doc = CreateObject("bpac.Document")
    
    If doc.Open(templatePath) = False Then
        MsgBox "Failed to open label"
        Exit Sub
    End If
    
    doc.SetPrinter "Brother QL-820NWB", True

    Dim r As Long
    r = ActiveCell.Row

    Call SetField(doc, "IMEI", Cells(r, 1).Value)
    Call SetField(doc, "Serial", Cells(r, 2).Value)
    Call SetField(doc, "Asset Tag", Cells(r, 3).Value)

    doc.StartPrint "", 0
    doc.PrintOut 1, 0
    doc.EndPrint
    
    doc.Close

End Sub

Sub PrintSmall()
    PrintLabel "C:\labels\small.lbx"
End Sub

Sub PrintLarge()
    PrintLabel "C:\labels\large.lbx"
End Sub
```

***

## 6. Add a Button (Optional)

1. Go to Insert → Shapes
2. Draw a rectangle
3. Right-click → Assign Macro
4. Choose PrintSmall or PrintLarge
5. Rename button (e.g. "Print Label")

***

## 7. How to Print

1. Click any cell in the row you want
2. Click your button OR run macro (ALT + F8)
3. Label prints

***

## 8. Common Issues

Error 91:

* Object name mismatch → check label object names

Label not printing:

* Printer name incorrect in:
  &#x20; doc.SetPrinter "Brother QL-820NWB", True

Template not loading:

* Check file path exists and is correct

Nothing happens:

* Enable macros when opening file

***

## 9. Tips

* Keep object names consistent across all labels
* Store all templates in one folder (e.g. C:\labels)
* You can add more fields later using SetField
