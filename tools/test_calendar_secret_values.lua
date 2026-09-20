local root=(arg[0]:gsub("tools[/\\]test_calendar_secret_values.lua$","")).."LIVE/Holy_Storm/"
local featureRoot=(arg[0]:gsub("tools[/\\]test_calendar_secret_values.lua$","")).."LIVE/Holy_Storm_Calendar/"

local Calendar={}
local locale=setmetatable({
 STATUS_CONFIRMED="Confirmed",STATUS_SIGNEDUP="Signed up",STATUS_TENTATIVE="Tentative",
 STATUS_STANDBY="Standby",STATUS_NOT_ATTENDING="Not attending",STATUS_UNKNOWN="Unavailable",
},{__index=function(_,key)return key end})
local queued={}
local HolyStorm={
 Database={Get=function()return{}end,Set=function()end},
 Events={Emit=function()end},
 Tasks={Enqueue=function(_,id,callback,options)queued[#queued+1]={id=id,callback=callback,options=options};return true end},
 PermissionEngine={Can=function()return false end},
 Policy={Can=function()return false end},
}
function HolyStorm:RegisterModule(_,factory)factory(Calendar);self.Calendar=Calendar end
function HolyStorm:ApplyModuleMetadata()end
function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
end

Enum={CalendarStatus={Invited=0,Available=1,Declined=2,Confirmed=3,Out=4,Standby=5,Signedup=6,NotSignedup=7,Tentative=8}}
assert(loadfile(featureRoot.."Calendar.lua"))()

-- Legacy clients without Secret Value predicates retain the old numeric/string behavior.
issecretvalue,canaccessvalue=nil,nil
assert(Calendar:NormalizeCalendarStatus(Enum.CalendarStatus.Confirmed)=="CONFIRMED","numeric CalendarStatus normalizes")
assert(Calendar:NormalizeCalendarStatus("SIGNEDUP")=="SIGNEDUP","legacy string CalendarStatus normalizes")
assert(Calendar:HasStatus(Enum.CalendarStatus.Confirmed,"Confirmed"),"numeric HasStatus remains unchanged")
assert(Calendar:IsSignedUp({inviteStatus="DECLINED"}),"known non-attending responses remain signed-up responses")
assert(not Calendar:IsActiveParticipant({inviteStatus="DECLINED"}),"declined remains inactive")

local secretMeta={
 __eq=function()error("secret status compared")end,
 __tostring=function()error("secret status serialized")end,
}
local secretStatus=setmetatable({secret=true},secretMeta)
local secretEnum=setmetatable({enum=true},secretMeta)
local oldConfirmed=Enum.CalendarStatus.Confirmed
Enum.CalendarStatus.Confirmed=secretEnum
issecretvalue=function(value)return rawequal(value,secretStatus)end
canaccessvalue=function(value)return not rawequal(value,secretStatus)end

assert(Calendar:NormalizeCalendarStatus(secretStatus)=="UNKNOWN","inaccessible status becomes UNKNOWN")
local ok,result=pcall(function()return Calendar:HasStatus(secretStatus,"Confirmed")end)
assert(ok and result==false,"HasStatus must not compare an inaccessible secret")
ok,result=pcall(function()return Calendar:GetStatusLabel(secretStatus)end)
assert(ok and result=="Unavailable","secret status has a neutral localized label")
ok,result=pcall(function()return Calendar:IsSignedUp({inviteStatus=secretStatus})end)
assert(ok and result==false,"secret status is not counted as signed up")
ok,result=pcall(function()return Calendar:IsActiveParticipant({inviteStatus=secretStatus})end)
assert(ok and result==false,"secret status is not counted as active")
Enum.CalendarStatus.Confirmed=oldConfirmed

local event={title="Raid",year=2026,month=9,monthDay=18,hour=20,minute=0,description="",allInvites={{name="A",inviteStatus=secretStatus,classFilename="MAGE"}}}
local fingerprint=Calendar:GetFingerprint(event)
assert(fingerprint:find("UNKNOWN",1,true),"fingerprint uses the neutral status marker")
assert(not fingerprint:find("secret",1,true),"fingerprint contains no secret representation")
local secondSecret=setmetatable({secret=true},secretMeta)
local oldIsSecret=issecretvalue
issecretvalue=function(value)return rawequal(value,secretStatus)or rawequal(value,secondSecret)end
event.allInvites[1].inviteStatus=secondSecret
assert(Calendar:GetFingerprint(event)==fingerprint,"inaccessible statuses have a stable deterministic fingerprint")
issecretvalue=oldIsSecret
event.allInvites[1].inviteStatus=Enum.CalendarStatus.Confirmed
assert(Calendar:GetFingerprint(event):find("CONFIRMED",1,true),"normal status remains represented in fingerprints")

-- The names-ready retry still runs, but its deferred callback normalizes rather than
-- comparing or retaining the Secret Value returned by EventGetInvite.
local namesReadyCalls,closed=0,0
C_Calendar={
 OpenEvent=function()return true end,
 AreNamesReady=function()namesReadyCalls=namesReadyCalls+1;return namesReadyCalls>1 end,
 GetEventInfo=function()return{description="Details",isLocked=false}end,
 GetRaidInfo=function()return nil end,
 EventCanEdit=function()return false end,
 GetNumInvites=function()return 1 end,
 EventGetInvite=function()return{name="Secret Player",inviteStatus=secretStatus,classFilename="MAGE"}end,
 CloseEvent=function()closed=closed+1 end,
}
function Calendar:IsEnabled()return true end
function Calendar:SetLoading()end
local originalFinishRefresh=Calendar.FinishRefresh
local finishedEvents
function Calendar:FinishRefresh(events)finishedEvents=events end
local events={{selection={offsetMonths=0,monthDay=18,eventIndex=1}}}
Calendar:LoadEventDetails(events,1)
assert(queued[1]and queued[1].id=="calendar.collect-details","detail collection is queued")
table.remove(queued,1).callback()
assert(queued[1]and queued[1].id=="calendar.names-ready","names-ready retry is queued")
table.remove(queued,1).callback()
assert(finishedEvents==events and closed==1,"retry path completes the refresh")
assert(events[1].signupCount==0,"unknown status is not counted")
assert(#events[1].allInvites==1 and events[1].allInvites[1].inviteStatus=="UNKNOWN","snapshot retains only normalized status")
assert(#events[1].invites==1,"unknown invite remains visible with its neutral UI status")

-- Finishing an asynchronous refresh must never hide Blizzard's protected CalendarFrame.
Calendar.FinishRefresh=originalFinishRefresh
Calendar.StoreSnapshot=function()return false end
Calendar.GetDatabase=function()return{}end
Calendar.SetLoading=function()end
Calendar.UpdateNotification=function()end
Calendar.detail={IsShown=function()return false end}
CalendarFrame={IsShown=function()return true end}
local blizzardHideCalls=0
HideUIPanel=function()blizzardHideCalls=blizzardHideCalls+1;error("protected frame hide attempted")end
ok,result=pcall(function()Calendar:FinishRefresh({})end)
assert(ok and blizzardHideCalls==0,"task refresh does not hide Blizzard CalendarFrame")

-- Holy Storm-owned frames remain independently showable/hideable.
local ownHides,ownShows,renders=0,0,0
local function ownFrame()
 return{Hide=function()ownHides=ownHides+1 end,Show=function()ownShows=ownShows+1 end}
end
Calendar.detailLayout={frame=ownFrame()};Calendar.detail=ownFrame();Calendar.heading=ownFrame();Calendar.filterBar=ownFrame();Calendar.scroll=ownFrame()
Calendar.Render=function()renders=renders+1 end
Calendar:ShowList()
assert(ownHides==2 and ownShows==3 and renders==1,"Holy Storm-owned frame navigation still works")

local source=assert(io.open(featureRoot.."Calendar.lua","rb")):read("*a")
assert(not source:find("HideUIPanel",1,true),"calendar task path contains no Blizzard panel hide")
print("Calendar Secret Value compatibility tests passed")
