string ver="DHv1.3.7";//LBA Version
integer mhp=200;//Maximum HP
integer hp=mhp;//Current HP
//Positive Numbers Deal Damage
//Negative Numbers Restore Health
//Damage Multipliers: 0 = Invulnerable, 1.0 = 100% Damage, High numbers = Higher Damage
//The total between all values should be around 5.0 for balancing purposes.
integer atcap=200;
float front=0.5;
float side=1.0;
float back=1.5;
float middle=0.1;
//Note that following modifiers multiply the final damage. So it stacks multiplicatively with the previous modifiers
float top=1.2;
float bottom=1.5;
//Directional Processor
float front_threshold=25.0;//Use positive floats, determines forward range
float back_threshold=155.0;//Use positive floats, determines backward range
float height_threshold=0.75;//How far up/down the Z axis should the source be to registered a top or bottom hit. Should be roughly half the vehicle's height to ground from root position.
float collisionmod(vector pos, vector targetPos)
{
    if(targetPos)
    {
        float dist=llVecDist(pos,targetPos);
        if(dist<1.0)return middle;//This catches explosions which rezzes AT in the object's root position.
        else
        {
            float mod=targetPos.z-pos.z;
            if(llFabs(mod)>=height_threshold)//Determines top/bottom hits
            {
                if(mod>0.0)mod=top;//Top check
                else mod=bottom;//Bottom check
            }
            else mod=1.0;//Else reset it to 1.0
            vector angle=<1.0,0.0,0.0>*llGetRot();
            angle.z=0.0;
            rotation targetRot=llRotBetween(llVecNorm(angle),llVecNorm(<targetPos.x,targetPos.y,pos.z>-pos));
            vector targetRotVec=llRot2Euler(targetRot)*RAD_TO_DEG;
            if(targetRotVec.z>-front_threshold&&targetRotVec.z<front_threshold)//Front
                return front*mod;
            else if(targetRotVec.z<-back_threshold||targetRotVec.z>back_threshold)//Back
                return back*mod;
            else //If it didn't hit any previous angles, the only thing left to hit is the sides.
                return side*mod;
        }
    }
    else return 0.0;
}
//Damage Processor
damage(integer amt, key id,vector pos, vector targetPos, float tmod, string name)
{
    if(amt>atcap)amt=atcap;
    if(amt<0)//Allows the object to be healed/repaired
    {
        if(llGetTime()>1.0)//Optional healing cooldown
        {
            if(amt>(float)hp*0.1)amt=llRound(hp*0.1);//Optional healing cap
            hp-=amt;
            if(hp>mhp)hp=mhp;//Used to prevent overhealing
            llResetTime();
        }
        //Be sure to update the listen event code block to allow negative damage values through.
    }
    /*else if(amt<6)return; //Blocks micro-LBA*/
    else
    {
        integer directional_amt;
        if(tmod)directional_amt=llFloor(amt*tmod);
        else directional_amt=llFloor(collisionmod(pos,targetPos)*(float)amt);
        if(directional_amt)hp-=directional_amt;
        else //Failed to do damage
        {
            llOwnerSay("Damage Blocked by Armor");
            llRegionSayTo(llGetOwnerKey(id),0,"Attack was stopped by armor.");
            return;
        }
        llOwnerSay("/me took "+(string)directional_amt+" ("+(string)amt+") damage from "+name+" by "+llKey2Name(llGetOwnerKey(id)));//Used to debug output.
        llRegionSayTo(llGetOwnerKey(id),0,"/me took "+(string)directional_amt+" ("+(string)amt+") damage");
    }
    if(hp<1)die();
    else update();
}
string modifierstring;//This is visible so moderators can confirm vehicle attributes are within regulation.
update()//SetText
{
    llSetLinkPrimitiveParamsFast(-4,[PRIM_TEXT,"[LBHD]\n "+(string)hp+" / "+(string)mhp+" HP",<0.0,0.75,1.0>,1.0,
        PRIM_DESC,"LBA.v."+ver+","+(string)hp+","+(string)mhp+","+(string)atcap+",999"+modifierstring]);
        //In order: Current HP, Max HP, Max AT accepted, Max healing accepted (Not implemented)
}
die()
{
    //Add extra shit here
    //llResetScript();//Debug
    llDie();//Otherwise, use this
}
integer los(vector start, vector target)//1=LoS,0=Obstructed
{
    list ray=llCastRay(start,target,[RC_REJECT_TYPES,RC_REJECT_AGENTS,RC_DATA_FLAGS,RC_GET_ROOT_KEY,RC_MAX_HITS,1]);
    if(llList2Vector(ray,1)==ZERO_VECTOR)return 1;
    else return 0;
}
vector tar(key id)//Deprecated
{
    vector av=(vector)((string)llGetObjectDetails(id,[OBJECT_POS]));
    return av;
}
key user;
key gen;//Object rezzer
key me;
integer hear;
list tracker;
boot()
{
    modifierstring=",F-"+llGetSubString((string)front,0,2)+//Frontal modifier
        ",S-"+llGetSubString((string)side,0,2)+//Side modifier
        ",R-"+llGetSubString((string)back,0,2)+//Rear modifier
        ",T-"+llGetSubString((string)top,0,2)+//Top modifier
        ",B-"+llGetSubString((string)bottom,0,2)+//Bottom modifier
        ",M-"+llGetSubString((string)middle,0,2);//Middle Modifier
    user=llGetOwner();
    me=llGetKey();
    gen=(string)llGetObjectDetails(me,[OBJECT_REZZER_KEY]);
    if(hear)llListenRemove(hear);
    integer hex=(integer)("0x" + llGetSubString(llMD5String((string)me,0), 0, 3));
    hear=llListen(hex,"","","");
    llSetTimerEvent(1.0);//Used for auto-delete.
    update();
}
default
{
    state_entry()
    {
        boot();
    }
    on_rez(integer p)
    {
        if(p>1)//Allows HUD/Objects to set HP value when rezzed with a param, otherwise uses default
        {
            mhp=p;
            hp=p;
        }
        boot();
    }
    listen(integer chan, string name, key id, string message)
    {
        //[ALWAYS] USE llRegionSayTo(). Do not flood the channel with useless garbage that'll poll every object in listening range.
        list parse=llParseString2List(message,[","],[" "]);
        if(llList2Key(parse,0)==me)//targetcheck
        {
            list data=llGetObjectDetails(id,[OBJECT_POS,OBJECT_ATTACHED_POINT,OBJECT_ROT]);
            vector pos=llGetPos();
            vector targetPos=llList2Vector(data,0);
            float tmod;
            integer f=llListFindList(tracker,[name]);
            if(f>-1)tmod=llList2Float(tracker,f+1);
            float amt=llList2Float(parse,-1);
            if(llFabs(amt)<666.0)
            {
                if(llList2Integer(data,1))
                {
                    float dist=llVecDist(targetPos,pos)-2.0;
                    vector posfix=targetPos+<dist,0.0,0.0>*llList2Rot(data,2);
                    if(los(pos,posfix))damage((integer)amt,id,pos,posfix,0.0,name);
                    else damage((integer)amt,id,pos,targetPos,0.0,name);
                }
                else damage((integer)amt,id,pos,targetPos,tmod,name);
            }
        }
    }
    collision_start(integer c)
    {
        if(llVecMag(llDetectedVel(0))>40.0)
        {
            vector gpos=llGetPos();
            if(tracker==[])llSetTimerEvent(1.0);
            string name=llDetectedName(0);
            integer f=llListFindList(tracker,[name]);
            if(f>-1)tracker=llListReplaceList(tracker,[collisionmod(gpos,llDetectedPos(0))],f+1,f+1);
            else
            {
                if(llGetListLength(tracker)>10)tracker=llDeleteSubList(tracker,0,1);//Delete eldest entry to prevent stack-heap
                tracker+=[name,collisionmod(gpos,llDetectedPos(0))];
            }
            //Stores data as follows: OBJECT_NAME,OBJECT_MODIFIER
            //Updates objects of the same name to the most recent.
        }
    }
    timer()//Auto-deleter. Will kill object if avatar leaves the region or spawning object is removed.
    {
        tracker=[];//Reset tracker
        if(tar(gen))return;
        llDie();
    }
}
