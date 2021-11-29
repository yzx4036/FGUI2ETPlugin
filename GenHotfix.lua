---
--- Created by Administrator.
--- DateTime: 2017/12/14 11:06
---

local print = print
local tconcat = table.concat
local tinsert = table.insert
local type = type
local pairs = pairs
local tostring = tostring
local next = next

local function pr (t, name, indent)
	local tableList = {}
	local function table_r (t, name, indent, full)
		local id = not full and name or type(name) ~= "number" and tostring(name) or '[' .. name .. ']'
		local tag = indent .. id .. ' = '
		local out = {}  -- result
		if type(t) == "table" then
			if tableList[t] ~= nil then
				tinsert(out, tag .. '{} -- ' .. tableList[t] .. ' (self reference)')
			else
				tableList[t] = full and (full .. '.' .. id) or id
				if next(t) then
					-- Table not empty
					tinsert(out, tag .. '{')
					for key, value in pairs(t) do
						tinsert(out, table_r(value, key, indent .. '|  ', tableList[t]))
					end
					tinsert(out, indent .. '}')
				else
					tinsert(out, tag .. '{}')
				end
			end
		else
			local val = type(t) ~= "number" and type(t) ~= "boolean" and '"' .. tostring(t) .. '"' or tostring(t)
			tinsert(out, tag .. val)
		end
		return tconcat(out, '\n')
	end
	return table_r(t, name or 'Value', indent or '')
end
local function print_r (t, name)
	fprint(pr(t, name))
end

---@param handler CS.FairyEditor.PublishHandler
local function genCode(handler)
	---@type CS.FairyEditor.GlobalPublishSettings.CodeGenerationConfig
	local settings = handler.project:GetSettings("Publish").codeGeneration
	local codePkgName = handler:ToFilename(handler.pkg.name); --convert chinese to pinyin, remove special chars etc.
	local exportCodePath = handler.exportCodePath .. '/' .. codePkgName
	local namespaceName = settings.packageName
	
	--CollectClasses(stripeMemeber, stripeClass, fguiNamespace)
	local classes = handler:CollectClasses(settings.ignoreNoname, settings.ignoreNoname, nil)
	handler:SetupCodeFolder(exportCodePath, "cs") --check if target folder exists, and delete old files
	
	local classNamePrefix = settings.classNamePrefix
	local getMemberByName = settings.getMemberByName
	local hasClassNamePrefix = classNamePrefix and string.len(classNamePrefix) > 0
	
	---默认是不能生成跨包的组件类型，这里查找component的正确类型保存到字典，供生成代码字段时检测
	local _typeDict = {}
	for i = 0, handler.pkg.items.Count - 1 do
		---@type CS.FairyEditor.FPackageItem
		local _item = handler.pkg.items[i]
		if string.find(_item.file, "xml") then
			local _itemXml = CS.FairyEditor.XMLExtension.Load(_item.file)
			if _itemXml then
				local displayList = _itemXml:GetNode("displayList")
				if displayList then
					local _itemName = _item.name
					if hasClassNamePrefix then
						_itemName = classNamePrefix .. _item.name --这里拼接一下全局设置里面类名前缀
					end
					_typeDict[_itemName] = _typeDict[_itemName] or {}
					---@type CS.FairyGUI.Utils.XML
					local _elem = displayList:Elements():Filter("component")
					for j = 0, _elem.Count - 1 do
						---@type CS.FairyGUI.Utils.XML
						local comp = _elem.rawList[j]
						local compNameKey = comp:GetAttribute("name")
						local compType = comp:GetAttribute("fileName")
						if compNameKey then
							compType = string.sub(compType, 1, string.len(compType) - 4)
							if hasClassNamePrefix then
								compType = classNamePrefix .. compType --这里拼接一下全局设置里面类名前缀
							end
							_typeDict[_itemName][compNameKey] = compType
						end
					end
				end
			end
		end
	end
	
	--print_r(_typeDict)
	
	local classCnt = classes.Count
	local writer = CodeWriter.new()
	for i = 0, classCnt - 1 do
		---@type CS.FairyEditor.PublishHandler.ClassInfo
		local classInfo = classes[i]
		local members = classInfo.members
		writer:reset()
		
		writer:writeln('using FairyGUI;')
		writer:writeln('using System.Threading.Tasks;')
		writer:writeln()
		writer:writeln('namespace %s', namespaceName)
		writer:startBlock()
		-- 1
		writer:writeln([[[ObjectSystem]
    public class %sAwakeSystem : AwakeSystem<%s, GObject>
    {
        public override void Awake(%s self, GObject go)
        {
            self.Awake(go);
        }
    }
        ]], classInfo.className, classInfo.className, classInfo.className)
		
		--如果是收藏的组件，生成[FUI]属性
		if classInfo.res.exported
				and classInfo.res.type == "component"
				and classInfo.res.favorite then
			writer:writeln(string.format("[FUI(typeof(%s), UIPackageName, UIResName)]", classInfo.className))
		end
		
		writer:writeln([[public sealed class %s : FUI
    {	
        public const string UIPackageName = "%s";
        public const string UIResName = "%s";
        
        /// <summary>
        /// {uiResName}的组件类型(GComponent、GButton、GProcessBar等)，它们都是GObject的子类。
        /// </summary>
        public %s self;
            ]], classInfo.className, codePkgName, classInfo.resName, classInfo.superClassName)
		
		local memberCnt = members.Count
		for j = 0, memberCnt - 1 do
			local memberInfo = members[j]
			_typeDict[classInfo.className] = _typeDict[classInfo.className] or {}
			local type = _typeDict[classInfo.className][memberInfo.varName] or memberInfo.type
			writer:writeln('    public %s %s;', type, memberInfo.varName)
		end
		writer:writeln([[    public const string URL = "ui://%s%s";]], handler.pkg.id, classInfo.resId)
		writer:writeln()
		
		writer:writeln([[    /// <summary>
        /// 通过此方法获取的FUI，在Dispose时不会释放GObject，需要自行管理（一般在配合FGUI的Pool机制时使用）。
        /// </summary>
        //public static %s GetFormPool(Entity domain, GObject go)
        //{
			//  var fui = go.Get<%s>();

            //if(fui == null)
            //{
			//  fui = Create(domain, go);
			//}

			//fui.isFromFGUIPool = true;

			//return fui;
		//}
        ]], classInfo.className, classInfo.className)
		
		writer:writeln([[    public void Awake(GObject go)
        {
            if(go == null)
            {
                return;
			}
        
			GObject = go;	
        
			if (string.IsNullOrWhiteSpace(Name))
			{
				Name = UIResName;
			}
        
			self = (%s)go;
        
			self.Add(this);
        
			var com = go.asCom;
            
			if(com != null)
			{]], classInfo.superClassName)
		
		--print_r(_typeDict)
		
		
		for j = 0, memberCnt - 1 do
			local memberInfo = members[j]
			
			_typeDict[classInfo.className] = _typeDict[classInfo.className] or {}
			local typeName = _typeDict[classInfo.className][memberInfo.varName] or memberInfo.type
			
			--fprint("className:"..classInfo.className.." varName:"..memberInfo.varName)
			
			local isCustomComponent = _typeDict[classInfo.className][memberInfo.varName] ~= nil
			
			if memberInfo.group == 0 then
				if getMemberByName then
					if isCustomComponent then
						writer:writeln('\t\t\t%s = AddChild<%s, GObject>(com.GetChildAt(%s));', memberInfo.varName, typeName, memberInfo.index)
						-- writer:writeln('\t\t%s = %s.Create(domain, com.GetChild("%s"));', memberInfo.varName, typeName, memberInfo.name)
					else
						writer:writeln('\t\t\t%s = (%s)com.GetChild("%s");', memberInfo.varName, typeName, memberInfo.name)
					end
				else
					if isCustomComponent then
						writer:writeln('\t\t\t%s = AddChild<%s, GObject>(com.GetChildAt(%s));', memberInfo.varName, typeName, memberInfo.index)
						-- writer:writeln('\t\t%s = %s.Create(domain, com.GetChildAt(%s));', memberInfo.varName, typeName, memberInfo.index)
					else
						writer:writeln('\t\t\t%s = (%s)com.GetChildAt(%s);', memberInfo.varName, typeName, memberInfo.index)
					end
				end
			elseif memberInfo.group == 1 then
				if getMemberByName then
					writer:writeln('\t\t\t%s = com.GetController("%s");', memberInfo.varName, memberInfo.name)
				else
					writer:writeln('\t\t\t%s = com.GetControllerAt(%s);', memberInfo.varName, memberInfo.index)
				end
			else
				if getMemberByName then
					writer:writeln('\t\t\t%s = com.GetTransition("%s");', memberInfo.varName, memberInfo.name)
				else
					writer:writeln('\t\t\t%s = com.GetTransitionAt(%s);', memberInfo.varName, memberInfo.index)
				end
			end
		end
		writer:writeln('\t\t}')
		
		writer:writeln('\t}')
		
		writer:writeln([[    public override void Dispose()
		{
            if(IsDisposed)
            {
                return;
            }
            
            base.Dispose();
            
            self.Remove();
            self = null;
            ]])
		
		for j = 0, memberCnt - 1 do
			local memberInfo = members[j]
			local typeName = memberInfo.type
			if memberInfo.group == 0 then
				if getMemberByName then
					if string.find(typeName, 'FUI') then
						writer:writeln('\t\t%s.Dispose();', memberInfo.varName)
					end
					writer:writeln('\t\t%s = null;', memberInfo.varName)
				else
					if string.find(typeName, 'FUI') then
						writer:writeln('\t\t%s.Dispose();', memberInfo.varName)
					end
					writer:writeln('\t\t%s = null;', memberInfo.varName)
				end
			elseif memberInfo.group == 1 then
				if getMemberByName then
					writer:writeln('\t\t%s = null;', memberInfo.varName)
				else
					writer:writeln('\t\t%s = null;', memberInfo.varName)
				end
			else
				if getMemberByName then
					writer:writeln('\t\t%s = null;', memberInfo.varName)
				else
					writer:writeln('\t\t%s = null;', memberInfo.varName)
				end
			end
		end
		writer:writeln('\t}')
		
		writer:endBlock() --class
		writer:endBlock() --namepsace
		
		writer:save(exportCodePath .. '/' .. classInfo.className .. '.cs')
	end
	
	-- 写入fuipackage
	writer:reset()
	
	writer:writeln('namespace %s', namespaceName)
	writer:startBlock()
	writer:writeln('public static partial class FUIPackage')
	writer:startBlock()
	
	writer:writeln('public const string %s = "%s";', codePkgName, codePkgName)
	
	-- 生成所有的
	local itemCount = handler.items.Count
	for i = 0, itemCount - 1 do
		writer:writeln('public const string %s_%s = "ui://%s/%s";', codePkgName, handler.items[i].name, codePkgName, handler.items[i].name)
	end
	
	writer:endBlock() --class
	writer:endBlock() --namespace
	local binderPackageName = 'Package' .. codePkgName
	writer:save(exportCodePath .. '/' .. binderPackageName .. '.cs')
	
	
	-- 写入Fui Type
	-- 生成所有的Type
	local itemCount = handler.items.Count
	local _genClassNameList = {}
	for i = 0, itemCount - 1 do
		---@type CS.FairyEditor.FPackageItem
		local _item = handler.items[i]
		if _item.exported and _item.type == "component" and _item.favorite then
			local _className = _item.name
			if hasClassNamePrefix then
				_className = classNamePrefix .. _className
			end
			table.insert(_genClassNameList, _className)
			writer:writeln('public static readonly Type %s = typeof(%s);', _className, _className)
		end
	end
	if #_genClassNameList > 0 then
		writer:reset()
		writer:writeln('using System;')
		
		writer:writeln('namespace %s', namespaceName)
		writer:startBlock()
		writer:writeln('public static partial class FUIType')
		writer:startBlock()
		
		for i = 1, #_genClassNameList do
			writer:writeln('public static readonly Type %s = typeof(%s);', _genClassNameList[i], _genClassNameList[i])
		end
		
		writer:endBlock() --class
		writer:endBlock() --namespace
		local binderPackageName = 'FUIType' .. codePkgName
		writer:save(exportCodePath .. '/' .. binderPackageName .. '.cs')
	end
	
	
	


end

return genCode
