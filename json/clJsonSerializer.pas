{
  Copyright (C) 2016 by Clever Components

  Author: Sergey Shirokov <admin@clevercomponents.com>

  Website: www.CleverComponents.com

  This file is part of Json Serializer.

  Json Serializer is free software: you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License version 3
  as published by the Free Software Foundation and appearing in the
  included file COPYING.LESSER.

  Json Serializer is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with Json Serializer. If not, see <http://www.gnu.org/licenses/>.
}


{
   Author: Alessandro Bruzzone

   13/02/2018
   Added deserialization mapping for float data type properties (native data "Double")
   22/03/2018
   Added case of null-boolean value in deserialization
   03/09/2021
   Now all public property are serializable by default without the necessity of define always the attribute
   Fixed Float property serialization
   Added TclJsonPrivate attribute to avoid property serialization
   28/09/2021
   Added TclJsonPrivate attribute Implementation also for Array and TObject property types
   30/09/2021
   In Serialize() now it's possible to override attributes of properties declared in a base class
      example to define a public property in base class as TclJsonPrivate in inherited class:
        TMyClass = class(TInterfacedObject)
        public
          [TclJsonprivate]
          property RefCount;
        end;
}


unit clJsonSerializer;

interface

uses
  System.Classes, System.SysUtils, System.StrUtils, System.DateUtils,
  System.Generics.Collections, System.Rtti, System.TypInfo,
  clJsonSerializerBase, clJsonParser;

type
  TclJsonPropertyOption = (clPrivate, clRequired);
  TclJsonPropertyOptions = set of TclJsonPropertyOption ;

  TclJsonTypeNameMapAttributeList = TArray<TclJsonTypeNameMapAttribute>;

  TclJsonSerializer = class(TclJsonSerializerBase)
  strict private
    function GetEncodedDate(aValue: Extended): string;
    function GetEncodedTime(aValue: Extended): string;
    function GetEncodedDateTime(aValue: Extended): string;
    function GetDecodedDate(const aValue: string): TDateTime;
    function GetDecodedTime(aValue: string): TDateTime;
    function GetDecodedDateTime(const aValue: string): TDateTime;

    procedure GetTypeAttributes(AType: TRttiType; var ATypeNameAttrs: TclJsonTypeNameMapAttributeList);
    procedure GetPropertyAttributes(AProp: TRttiProperty; var APropAttr: TclJsonPropertyAttribute;
      var APropertyOptions: TclJsonPropertyOptions);
    function GetObjectClass(ATypeNameAttrs: TclJsonTypeNameMapAttributeList; AJsonObject: TclJSONObject): TRttiType;

    procedure SerializeArray(AProperty: TRttiProperty; AObject: TObject;
      Attribute: TclJsonPropertyAttribute; AJson: TclJsonObject; ARequired: Boolean=False);
    procedure DeserializeArray(AProperty: TRttiProperty; AObject: TObject; AJsonArray: TclJSONArray);

    function Deserialize(AType: TClass; const AJson: TclJSONObject): TObject; overload;
    function Deserialize(AObject: TObject; const AJson: TclJSONObject): TObject; overload;
    function Serialize(AObject: TObject; ARequired: Boolean=False): TclJSONObject;
  public
    function JsonToObject(AType: TClass; const AJson: string): TObject; overload; override;
    function JsonToObject(AObject: TObject; const AJson: string): TObject; overload; override;
    function ObjectToJson(AObject: TObject): string; override;
  end;

resourcestring
  cUnsupportedDataType = 'Unsupported data type';
  cNonSerializable = 'The object is not serializable';

implementation

{ TclJsonSerializer }

function TclJsonSerializer.GetDecodedDate(const aValue: string): TDateTime;
begin
  if not TryISO8601ToDate(aValue, Result, True) then
    Result := 0.0
  else
    Result := DateOf(Result);
end;

function TclJsonSerializer.GetDecodedDateTime(const aValue: string): TDateTime;
begin
  if not TryISO8601ToDate(aValue, Result, True) then
    Result := 0.0;
end;

function TclJsonSerializer.GetDecodedTime(aValue: string): TDateTime;
begin
  if Pos('T', aValue) < Low(string) then
    aValue := '2000-01-01T'+aValue;

  if not TryISO8601ToDate(aValue, Result, True) then
    Result := 0.0
  else
    Result := TimeOf(Result);
end;

function TclJsonSerializer.GetEncodedDate(aValue: Extended): string;
begin
  if aValue = 0.0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy"-"mm"-"dd', aValue);
end;

function TclJsonSerializer.GetEncodedDateTime(aValue: Extended): string;
begin
  if aValue = 0.0 then
    Result := ''
  else
    Result := DateToISO8601(aValue,True);
end;

function TclJsonSerializer.GetEncodedTime(aValue: Extended): string;
begin
  Result := FormatDateTime('hh":"nn":"ss"."zzz', aValue);
end;

function TclJsonSerializer.GetObjectClass(ATypeNameAttrs: TclJsonTypeNameMapAttributeList; AJsonObject: TclJSONObject): TRttiType;
var
  ctx: TRttiContext;
  typeName: string;
  attr: TclJsonTypeNameMapAttribute;
begin
  Result := nil;
  if (ATypeNameAttrs = nil) or (Length(ATypeNameAttrs) = 0) then Exit;

  typeName := AJsonObject.ValueByName(ATypeNameAttrs[0].PropertyName);
  if (typeName = '') then Exit;

  ctx := TRttiContext.Create();
  try
    for attr in ATypeNameAttrs do
    begin
      if (attr.TypeName = typeName) then
      begin
        Result := ctx.FindType(attr.TypeClassName);
        Exit;
      end;
    end;
  finally
    ctx.Free()
  end;
end;

procedure TclJsonSerializer.DeserializeArray(AProperty: TRttiProperty;
  AObject: TObject; AJsonArray: TclJSONArray);
var
  elType: PTypeInfo;
  len: NativeInt;
  pArr: Pointer;
  rValue, rItemValue: TValue;
  i: Integer;
  objClass: TClass;
begin
  len := AJsonArray.Count;
  if (len = 0) then Exit;

  if (GetTypeData(AProperty.PropertyType.Handle).DynArrElType = nil) then Exit;

  elType := GetTypeData(AProperty.PropertyType.Handle).DynArrElType^;

  pArr := nil;

  DynArraySetLength(pArr, AProperty.PropertyType.Handle, 1, @len);
  try
    TValue.Make(@pArr, AProperty.PropertyType.Handle, rValue);

    for i := 0 to AJsonArray.Count - 1 do
    begin
      if (elType.Kind = tkClass)
        and (AJsonArray.Items[i] is TclJSONObject) then
      begin
        objClass := elType.TypeData.ClassType;
        rItemValue := Deserialize(objClass, TclJSONObject(AJsonArray.Items[i]));
      end else
      if (elType.Kind in [tkString, tkLString, tkWString, tkUString]) then
      begin
        rItemValue := AJsonArray.Items[i].ValueString;
      end else
      if (elType.Kind = tkInteger) then
      begin
        rItemValue := StrToInt(AJsonArray.Items[i].ValueString);
      end else
      if (elType.Kind = tkInt64) then
      begin
        rItemValue := StrToInt64(AJsonArray.Items[i].ValueString);
      end else
      if (elType.Kind = tkEnumeration)
        and (elType = System.TypeInfo(Boolean))
        and (AJsonArray.Items[i] is TclJSONBoolean) then
      begin
        rItemValue := TclJSONBoolean(AJsonArray.Items[i]).Value;
      end else
      if  (elType.Kind = tkFloat) then
      begin
        rItemValue := StrToFloat( AnsiReplaceStr(AJsonArray.Items[i].ValueString,'.', FormatSettings.DecimalSeparator) );
      end else
      begin
        raise EclJsonSerializerError.Create(cUnsupportedDataType);
      end;

      rValue.SetArrayElement(i, rItemValue);
    end;

    AProperty.SetValue(AObject, rValue);
  finally
    DynArrayClear(pArr, AProperty.PropertyType.Handle);
  end;
end;

function TclJsonSerializer.JsonToObject(AObject: TObject; const AJson: string): TObject;
var
  obj: TclJSONObject;
begin
  obj := TclJSONBase.ParseObject(AJson);
  try
    Result := Deserialize(AObject, obj);
  finally
    obj.Free();
  end;
end;

function TclJsonSerializer.JsonToObject(AType: TClass; const AJson: string): TObject;
var
  obj: TclJSONObject;
begin
  obj := TclJSONBase.ParseObject(AJson);
  try
    Result := Deserialize(AType, obj);
  finally
    obj.Free();
  end;
end;

function TclJsonSerializer.ObjectToJson(AObject: TObject): string;
var
  json: TclJSONObject;
begin
  json := Serialize(AObject);
  try
    Result := json.GetJSONString();
  finally
    json.Free();
  end;
end;

function TclJsonSerializer.Deserialize(AType: TClass; const AJson: TclJSONObject): TObject;
var
  ctx: TRttiContext;
  lType, rType: TRttiType;
  instType: TRttiInstanceType;
  rValue: TValue;
  typeNameAttrs: TclJsonTypeNameMapAttributeList;
begin
  Result := nil;
  if (AJson.Count = 0) then Exit;

  ctx := TRttiContext.Create();
  try
    rType := ctx.GetType(AType);

    GetTypeAttributes(rType, typeNameAttrs);
    lType := GetObjectClass(typeNameAttrs, AJson);
    if (lType = nil) then
    begin
      lType := rType;
    end;
    instType := lType.AsInstance;
    rValue := instType.GetMethod('Create').Invoke(instType.MetaclassType, []);

    Result := rValue.AsObject;
    try
      Result := Deserialize(Result, AJson);
    except
      Result.Free();
      raise;
    end;
  finally
    ctx.Free();
  end;
end;

function TclJsonSerializer.Deserialize(AObject: TObject; const AJson: TclJSONObject): TObject;
var
  ctx: TRttiContext;
  rType: TRttiType;
  rProp: TRttiProperty;
  member: TclJSONPair;
  rValue: TValue;
  objClass: TClass;
  nonSerializable: Boolean;
  propAttr: TclJsonPropertyAttribute;
  propOptions: TclJsonPropertyOptions;
  ownPropAttr: Boolean;
begin
  Result := AObject;

  if (AJson.Count = 0) or (Result = nil) then Exit;

  nonSerializable := True;

  ctx := TRttiContext.Create();
  try
    rType := ctx.GetType(Result.ClassInfo);

    for rProp in rType.GetProperties() do
    begin
      if not rProp.IsWritable then
        Continue;

      GetPropertyAttributes(rProp, propAttr, propOptions);

      if clPrivate in propOptions then
        Continue;

      // Added all public properties serializable by default
      if (propAttr = nil) and (rProp.Visibility in [mvPublic, mvPublished]) then
      begin
        ownPropAttr := True;
        if (rProp.PropertyType.TypeKind in [tkString, tkLString, tkWString, tkUString]) then
          propAttr := TclJsonStringAttribute.Create(rProp.Name)
        else
          propAttr := TclJsonPropertyAttribute.Create(rProp.Name);
      end
      else
        ownPropAttr := False;

     try
      if (propAttr <> nil) then
      begin
        nonSerializable := False;

        member := AJson.MemberByName(TclJsonPropertyAttribute(propAttr).Name);
        if (member = nil) then Continue;

        if (rProp.PropertyType.TypeKind = tkDynArray)
          and (member.Value is TclJSONArray) then
        begin
          DeserializeArray(rProp, Result, TclJSONArray(member.Value));
        end else
        if (rProp.PropertyType.TypeKind = tkClass)
          and (member.Value is TclJSONObject) then
        begin
          objClass := rProp.PropertyType.Handle^.TypeData.ClassType;
          rValue := Deserialize(objClass, TclJSONObject(member.Value));
          rProp.SetValue(Result, rValue);
        end else
        if (rProp.PropertyType.TypeKind in [tkString, tkLString, tkWString, tkUString]) then
        begin
          rValue := member.ValueString;
          rProp.SetValue(Result, rValue);
        end else
        if (rProp.PropertyType.TypeKind = tkInteger) then
        begin
          rValue := StrToInt(member.ValueString);
          rProp.SetValue(Result, rValue);
        end else
        if (rProp.PropertyType.TypeKind = tkInt64) then
        begin
          rValue := StrToInt64(member.ValueString);
          rProp.SetValue(Result, rValue);
        end else
        if (rProp.PropertyType.TypeKind = tkEnumeration)
          and (rProp.GetValue(Result).TypeInfo = System.TypeInfo(Boolean)) then
        begin
          if (member.Value is TclJSONBoolean) then
            rValue := TclJSONBoolean(member.Value).Value
          else
            rValue := false;

          rProp.SetValue(Result, rValue);
        end else
        if (rProp.PropertyType.TypeKind = tkEnumeration) then
        begin
;
          rProp.SetValue(Result, TValue.FromOrdinal( rProp.PropertyType.Handle, StrToInt(member.ValueString)));
        end else
        if SameText(rProp.PropertyType.Name, 'TDate') then
        begin
          rValue := GetDecodedDate(member.ValueString);
          rProp.SetValue(Result, rValue);
        end else
        if SameText(rProp.PropertyType.Name, 'TTime') then
        begin
          rValue := GetDecodedTime(member.ValueString);
          rProp.SetValue(Result, rValue);
        end else
        if SameText(rProp.PropertyType.Name, 'TDateTime') then
        begin
          rValue := GetDecodedDateTime(member.ValueString);
          rProp.SetValue(Result, rValue);
        end else
        if (rProp.PropertyType.TypeKind = tkFloat) then
        begin
          rValue := StrToFloat( AnsiReplaceStr(member.ValueString,'.', FormatSettings.DecimalSeparator) );
          rProp.SetValue(Result, rValue);
        end else
        begin
          raise EclJsonSerializerError.Create(cUnsupportedDataType + ' ('+member.Name+')');
        end;
      end;
     finally
       if ownPropAttr then
         propAttr.Free;
     end;
    end;
  finally
    ctx.Free();
  end;

  if (nonSerializable) then
  begin
    raise EclJsonSerializerError.Create(cNonSerializable);
  end;
end;

procedure TclJsonSerializer.GetPropertyAttributes(AProp: TRttiProperty; var APropAttr: TclJsonPropertyAttribute;
  var APropertyOptions: TclJsonPropertyOptions);
var
  attr: TCustomAttribute;
begin
  APropAttr := nil;
  APropertyOptions := [];

  for attr in AProp.GetAttributes() do
  begin
    if (attr is TclJsonPropertyAttribute) then
      APropAttr := attr as TclJsonPropertyAttribute;

    if (attr is TclJsonRequiredAttribute) then
      Include(APropertyOptions, clRequired);

    if (attr is TclJsonPrivateAttribute) then
      Include(APropertyOptions, clPrivate);
  end;
end;

procedure TclJsonSerializer.GetTypeAttributes(AType: TRttiType; var ATypeNameAttrs: TclJsonTypeNameMapAttributeList);
var
  attr: TCustomAttribute;
  list: TList<TclJsonTypeNameMapAttribute>;
begin
  list := TList<TclJsonTypeNameMapAttribute>.Create();
  try
    for attr in AType.GetAttributes() do
    begin
      if (attr is TclJsonTypeNameMapAttribute) then
      begin
        list.Add(attr as TclJsonTypeNameMapAttribute);
      end;
    end;
    ATypeNameAttrs := list.ToArray();
  finally
    list.Free();
  end;
end;

function TclJsonSerializer.Serialize(AObject: TObject; ARequired: Boolean): TclJSONObject;
const
  SEP = '|';
var
  ctx: TRttiContext;
  rType: TRttiType;
  rProp: TRttiProperty;
  nonSerializable: Boolean;
  propAttr: TclJsonPropertyAttribute;
  propOptions: TclJsonPropertyOptions;
  ownPropAttr: Boolean;
  inheritedProperties: string;
begin
  if (AObject = nil) then
  begin
    if ARequired then
      Result := TclJSONObject.Create()
    else
      Result := nil;
    Exit;
  end;

  nonSerializable := True;
  inheritedProperties := SEP;

  ctx := TRttiContext.Create();
  try
    Result := TclJSONObject.Create();
    try
      rType := ctx.GetType(AObject.ClassInfo);
      for rProp in rType.GetProperties() do
      begin
        if not rProp.IsReadable then
          Continue;

        if Pos(SEP+Lowercase(rProp.Name)+SEP, inheritedProperties) >= Low(string) then
          Continue;

        inheritedProperties := inheritedProperties + Lowercase(rProp.Name)+SEP;

        GetPropertyAttributes(rProp, propAttr, propOptions);

        if clPrivate in propOptions then
          Continue;

        // Added all public properties serializable by default
        if (propAttr = nil) and (rProp.Visibility in [mvPublic, mvPublished]) then
        begin
          ownPropAttr := True;
          if (rProp.PropertyType.TypeKind in [tkString, tkLString, tkWString, tkUString]) then
            propAttr := TclJsonStringAttribute.Create(rProp.Name)
          else
            propAttr := TclJsonPropertyAttribute.Create(rProp.Name);
        end
        else
          ownPropAttr := False;

       try
        if (propAttr <> nil) then
        begin
          nonSerializable := False;

          if (rProp.PropertyType.TypeKind = tkDynArray) then
          begin
            SerializeArray(rProp, AObject, TclJsonPropertyAttribute(propAttr), Result, (clRequired in propOptions));
          end else
          if (rProp.PropertyType.TypeKind = tkClass) then
          begin
            Result.AddMember(TclJsonPropertyAttribute(propAttr).Name, Serialize(rProp.GetValue(AObject).AsObject(), (clRequired in propOptions)));
          end else
          if (rProp.PropertyType.TypeKind in [tkString, tkLString, tkWString, tkUString]) then
          begin
            if (propAttr is TclJsonStringAttribute) then
            begin
              if clRequired in propOptions then
              begin
                Result.AddRequiredString(TclJsonPropertyAttribute(propAttr).Name, rProp.GetValue(AObject).AsString());
              end else
              begin
                Result.AddString(TclJsonPropertyAttribute(propAttr).Name, rProp.GetValue(AObject).AsString());
              end;
            end else
            begin
              Result.AddValue(TclJsonPropertyAttribute(propAttr).Name, rProp.GetValue(AObject).AsString());
            end;
          end else
          if (rProp.PropertyType.TypeKind in [tkInteger, tkInt64]) then
          begin
            Result.AddValue(TclJsonPropertyAttribute(propAttr).Name, rProp.GetValue(AObject).ToString());
          end else
          if (rProp.PropertyType.TypeKind = tkEnumeration)
            and (rProp.GetValue(AObject).TypeInfo = System.TypeInfo(Boolean)) then
          begin
            Result.AddBoolean(TclJsonPropertyAttribute(propAttr).Name, rProp.GetValue(AObject).AsBoolean());
          end else
          if (rProp.PropertyType.TypeKind = tkEnumeration) then
          begin
            Result.AddValue(propAttr.Name, rProp.GetValue(AObject).AsOrdinal.ToString);
          end else
          if SameText(rProp.PropertyType.Name, 'TDate') then
          begin
            Result.AddString(TclJsonPropertyAttribute(propAttr).Name, GetEncodedDate(rProp.GetValue(AObject).AsExtended));
          end else
          if SameText(rProp.PropertyType.Name, 'TTime') then
          begin
            Result.AddString(TclJsonPropertyAttribute(propAttr).Name, GetEncodedTime(rProp.GetValue(AObject).AsExtended));
          end else
          if SameText(rProp.PropertyType.Name, 'TDateTime') then
          begin
            Result.AddString(TclJsonPropertyAttribute(propAttr).Name, GetEncodedDateTime(rProp.GetValue(AObject).AsExtended));
          end else
          if (rProp.PropertyType.TypeKind = tkFloat) then
          begin
            Result.AddValue(TclJsonPropertyAttribute(propAttr).Name, AnsiReplaceStr(rProp.GetValue(AObject).ToString(),FormatSettings.DecimalSeparator,'.'));
          end else
          begin
            raise EclJsonSerializerError.Create(cUnsupportedDataType);
          end;
        end;

       finally
         if ownPropAttr then
           propAttr.Free;
       end;
      end;

      if (nonSerializable) then
      begin
        raise EclJsonSerializerError.Create(cNonSerializable);
      end;
    except
      Result.Free();
      raise;
    end;
  finally
    ctx.Free();
  end;
end;

procedure TclJsonSerializer.SerializeArray(AProperty: TRttiProperty; AObject: TObject;
  Attribute: TclJsonPropertyAttribute; AJson: TclJsonObject; ARequired: Boolean);
var
  rValue: TValue;
  i: Integer;
  arr: TclJSONArray;
begin
  rValue := AProperty.GetValue(AObject);

  if (rValue.GetArrayLength() > 0) or ARequired then
  begin
    arr := TclJSONArray.Create();
    AJson.AddMember(Attribute.Name, arr);

    for i := 0 to rValue.GetArrayLength() - 1 do
    begin
      if (rValue.GetArrayElement(i).Kind = tkClass) then
      begin
        arr.Add(Serialize(rValue.GetArrayElement(i).AsObject()));
      end else
      if (rValue.GetArrayElement(i).Kind in [tkString, tkLString, tkWString, tkUString]) then
      begin
        if (Attribute is TclJsonStringAttribute) then
        begin
          arr.Add(TclJSONString.Create(rValue.GetArrayElement(i).AsString()));
        end else
        begin
          arr.Add(TclJSONValue.Create(rValue.GetArrayElement(i).AsString()));
        end;
      end else
      if (rValue.GetArrayElement(i).Kind in [tkInteger, tkInt64]) then
      begin
        arr.Add(TclJSONValue.Create(rValue.GetArrayElement(i).ToString()));
      end else
      if (rValue.GetArrayElement(i).Kind = tkEnumeration)
        and (rValue.GetArrayElement(i).TypeInfo = System.TypeInfo(Boolean)) then
      begin
        arr.Add(TclJSONBoolean.Create(rValue.GetArrayElement(i).AsBoolean()));
      end else
      begin
        raise EclJsonSerializerError.Create(cUnsupportedDataType);
      end;
    end;
  end;
end;

end.
