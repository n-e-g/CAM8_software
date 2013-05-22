unit icx453;

interface

uses Classes, SysUtils, MyD2XX, Windows;

const CameraWidth  = 3000;    //������ �����������
      CameraHeight = 2000;    //������ �����������
      portfirst = $a1;        //�������������� �������� �� ������� ����� BDBUS
      portsecond = $c1;
      xccd = 1500;
      yccd = 1000;
      dx = 3044-2*xccd;
      dx2 = 1586-xccd;
      dy = 512-(yccd div 2);
      apolosa = 50;

type  camera_image_type = array [0..CameraWidth-1,0..CameraHeight-1] of integer;     //driver image type

      {Class for reading thread}
      posl = class(TThread)
      private
      { Private declarations }
      protected
      procedure Execute; override;
      end;
{GLobal variables}
var   IsConnected : boolean = false;        //����������-����, ���������� ��������� ���������� � �������
      adress : integer;                     //��������� �������� ������ � �������� ������ FT2232HL
      mBin : integer;                       //�������,
      mImageReady : boolean = false;        //����������-����, ���������� ���������� � ���������� �����
      mCameraState : integer = 0;           //����������-��������� ������
      ExposureTimer, Timer15V : integer;    //������ ���������� � 15� ������
      co: posl;                             //���������� ��� ������� ������ (������ �����������)
      bufim:camera_image_type;              //�������� ������-����������� ��� ��������
      mYn,mdeltY:integer;                   //������ ������ � ���������� �� �������
      mXn,mdeltX:integer;                   //������ ������ � ���������� �� ��������

{ ��������� ��������� ������ � FT2232LH.
 ������ ������������ ����� �����:
  1. ������� ����������� ����� � ��������� ������� (����������� ������������������ ��������� �� ������� ����� BDBUS).
��� ���� ���������������� ��������� adress.
  2. ����� ���� ���� ������ ���������� �� ����� ��������: n:=Write_USB_Device_Buffer(FT_CAM8B,adress);
������������� ���������� FT2232HL ������ ��� �������� ��� ��� �������� �� ���� ���� BDBUS. �������� 1 ����� ��� ���� �������� 65 ��.
����� ��������� ��������� ������� n:=Write_USB_Device_Buffer(FT_CAM8B,adress) ������� �� ������������� ����������� � �� ��������������
����. ������� ����������� ������������������ ��������� ����� ��������� ���, � �� ���������� �� �������.
����� ���������� ����� �������� ��� ��������� (� ���� ��������� �� 24 �����!) ��� ����� ����� �������� ����� D2XX.pas, � ������ ��� MyD2XX.pas}

function CameraConnect: WordBool;
function CameraDisconnect: WordBool;
function CameraSetGain (val : integer) : WordBool;
function CameraSetOffset (val : integer) : WordBool;
function CameraGetCameraState : integer;
function CameraStartExposure (Bin,StartX,StartY,NumX,NumY : integer; Duration : double; light : WordBool) : WordBool;
function CameraGetImageReady (var frame : camera_image_type) : WordBool;

implementation

procedure posl.Execute;                                     //���������� ���� ������ ������� ����� ���� ADBUS
{ ������ �������������� ���������� ������ FT2232HL � �������� ������ �����������
  ��-�� ������������ AD9822 ��������� ������� ������� ����, ����� �������, � � delphi ��������.
  ���������� �����  ��� integer32, � �� word16 ��-�� ������������ ��� ����������� ��������� }
var
x,y,x1:word;
begin
 for y:= mYn to mYn+mdeltY-1 do
  begin
   if mbin = 1 then
    begin
     Read_USB_Device_Buffer(FT_CAM8A,8*mdeltX);
     for x:=0 to mdeltX - 1 do
      begin
       x1:=x+mXn;
       bufim[2*x1,2*y]:=swap(FT_In_Buffer[4*x]);
       bufim[2*x1,2*y+1]:=swap(FT_In_Buffer[4*x+1]);
       bufim[2*x1+1,2*y+1]:=swap(FT_In_Buffer[4*x+2]);
       bufim[2*x1+1,2*y]:=swap(FT_In_Buffer[4*x+3]);
      end;
    end        else
    begin
     Read_USB_Device_Buffer(FT_CAM8A,2*mdeltX);
     for x:=0 to mdeltX - 1 do
      begin
       x1:=x+mXn;
       bufim[2*x1,2*y]:=swap(FT_In_Buffer[x]);
       bufim[2*x1+1,2*y]:=swap(FT_In_Buffer[x]);
       bufim[2*x1+1,2*y+1]:=swap(FT_In_Buffer[x]);
       bufim[2*x1,2*y+1]:=swap(FT_In_Buffer[x]);
      end;
    end;
  end;

end;

//�������� ������ � ���������������
procedure ComRead;
begin
  co:=posl.Create(true);
  co.FreeOnTerminate:=true;
  co.Priority:=tpLower;//Normal;
  co.Resume;
end;

{���������� ��������� ������ �������� ��� �������� � ���������� ����� val �� ������ adr � ���������� AD9822.
 �������� ���� � ���������������� ����.}
procedure AD9822(adr:byte;val:word);
const
kol = 64;
var
dan:array[0..kol-1] of byte;
i:integer;
begin
 fillchar(dan,kol,portfirst);                                   //����������� ������ �������������� ��������� �� ������� ����� BDBUS
 for i:=1 to 32 do dan[i]:=dan[i] and $fe;
 for i:=0 to 15 do dan[2*i+2]:=dan[2*i+2] + 2;
 if (adr and 4) = 4 then begin dan[3]:=dan[3]+4;dan[4]:=dan[4]+4;end;
 if (adr and 2) = 2 then begin dan[5]:=dan[5]+4;dan[6]:=dan[6]+4;end;
 if (adr and 1) = 1 then begin dan[7]:=dan[7]+4;dan[8]:=dan[8]+4;end;

 if (val and 256) = 256 then begin dan[15]:=dan[15]+4;dan[16]:=dan[16]+4;end;
 if (val and 128) = 128 then begin dan[17]:=dan[17]+4;dan[18]:=dan[18]+4;end;
 if (val and 64) = 64 then begin dan[19]:=dan[19]+4;dan[20]:=dan[20]+4;end;
 if (val and 32) = 32 then begin dan[21]:=dan[21]+4;dan[22]:=dan[22]+4;end;
 if (val and 16) = 16 then begin dan[23]:=dan[23]+4;dan[24]:=dan[24]+4;end;
 if (val and 8) = 8 then begin dan[25]:=dan[25]+4;dan[26]:=dan[26]+4;end;
 if (val and 4) = 4 then begin dan[27]:=dan[27]+4;dan[28]:=dan[28]+4;end;
 if (val and 2) = 2 then begin dan[29]:=dan[29]+4;dan[30]:=dan[30]+4;end;
 if (val and 1) = 1 then begin dan[31]:=dan[31]+4;dan[32]:=dan[32]+4;end;

 Write_USB_Device_Buffer(FT_CAM8B,@dan, kol);
end;

procedure HC595(val:byte);
{���������� ��������� ������ �������� ��� �������� ����� val �� ������ ���������� HC595.
 �������� ���� � ���������������� ����.}
const
kol = 18;
var
dan:array[0..kol-1] of byte;
i:integer;
begin
 fillchar(dan,kol,portfirst);                                    //����������� ������ �������������� ��������� �� ������� ����� BDBUS
 for i:=0 to 7 do
  begin
   dan[2*i+1]:=dan[2*i+1] + 2;
   if (val and $80) = $80 then begin dan[2*i]:=dan[2*i] + 4;dan[2*i+1]:=dan[2*i+1] + 4; end;
   val:=val*2;
  end;
   dan[16]:=dan[16]+ $80;
//   dan[17]:=dan[17]+ $80;

 for i:=0 to kol-1 do
  begin
   FT_Out_Buffer[2*i+adress]:=dan[i];
   FT_Out_Buffer[2*i+adress+1]:=dan[i];
  end;
 adress:=adress+2*kol;
end;

procedure shift0;
begin
// HC595($e9);
 HC595($ed);
// HC595($ad);
 HC595($af);
// HC595($ab);
 HC595($bb);
// HC595($b9);
 HC595($f9);
end;

procedure shift;
{���������� ��������� ������ �������� ��� ������ ���� ������������� ������}
begin
 HC595($e9);
 HC595($ed);
 HC595($ad);
 HC595($af);
 HC595($ab);
 HC595($bb);
 HC595($b9);
 HC595($f9);
end;

procedure shift2;
{���������� ��������� ������ �������� ��� "�����" ������������ ����������� � ��������� �������}
begin
 shift;
 HC595($f1);
 HC595($f1);
 HC595($f1);
 HC595($f1);
 HC595($e9);
 HC595($cd);
 HC595($cd);
 HC595($cd);
 HC595($cd);
 HC595($ed);
 HC595($af);//79);
 HC595($ab);//69);
 HC595($bb);//6d);
 HC595($b9);//2d);
 HC595($f9);//2f);
end;

procedure shift3;
{���������� ��������� ������ �������� ��� ������ ���� ������������� ������ + ������ SUB ��� ������ ������� �����������}
begin
 HC595($e9);
 HC595($ed);
 HC595($ac);//2d);SUB
 HC595($ae);//2f);
 HC595($aa);//2b);
 HC595($bb);
 HC595($b9);
 HC595($f9);
end;

procedure clearline;
{���������� ��������� ������ �������� ���:
 ������� ��������������� ������. ���� ��� �� ��������,
 �� ����������� � ��� ���������� ����� ����� �������� � ������ ������ �����������}
const
dout : array[0..1] of byte = (portsecond,portfirst);
var
x:word;
begin
 for x:=0 to 6000+192-1+200 do
 begin
  FT_Out_Buffer[adress+0]:=dout[0];
  FT_Out_Buffer[adress+1]:=dout[1];
  inc(adress,2);
 end;
end;

procedure clearframe;
{���������� ��������� ������ �������� ���:
 ������� ���������� ��������. ���� ��� �� ��������,
 �� ����������� � ��� ����� ����� �������� � �����������.
 ��������� ���� ������� ������ � "�������" � ��������������� ��������.
 �������� ���������� ����� "������" ����������� � ��������� �������.}
var
y:word;
begin
 for y:=0 to 1012-1 do shift;
 clearline;
end;

procedure clearline2;
const
dout : array[0..3] of byte = (portsecond,portsecond+8,portfirst+8,portfirst);
var x:integer;
begin

 for x:=0 to 79*xccd do
  begin
   FT_Out_Buffer[adress+0]:=dout[0]+$10;
   FT_Out_Buffer[adress+1]:=dout[1]+$10;
   FT_Out_Buffer[adress+2]:=dout[2]+$10;
   FT_Out_Buffer[adress+3]:=dout[3]+$10;
   inc(adress,4);
  end;

end;

{������������ 2 ������:
 1.������� ��� �������.
 2.�/� � �������� 2*2.
 ������������ ������� ICX453 �������� ��, ��� �������������� ������� ����� ��������� ������� �
 ��� ����� ���� ������������� ������ � �������������� ������� "������" ����� ���� �����,
 ������� ���������� ����� ��� ���� ���� �������� ����������.
 ������������ ��������:
  readframe, display, display2 - ��� 1 ������,
  readframe2, display3, display4 - ��� 2 ������}


{���������� ��������� ������ �������� � ���������� ���� �������� ������ ����� � 1 ������}
procedure readframe(bin:integer;expoz:integer);
const
dout : array[0..4] of byte = (portsecond,portsecond+8,portfirst+8,portfirst,portsecond+$28);
var x,y:integer;
begin
//camera reading ccd
mCameraState := 3;

Purge_USB_Device_In(FT_CAM8A);
Purge_USB_Device_OUT(FT_CAM8A);
Purge_USB_Device_OUT(FT_CAM8B);

adress:=0;
if expoz > 52 then
 begin
  if expoz < 500 then
   begin
    shift3;
    for y:=0 to expoz-52 do
    for x:=0 to 416 do HC595($f9);
   end; 
  clearline2;
  clearframe;
 end         else
 begin
  clearline2;
  clearframe;
  shift3;
  if expoz > 0 then
  for y:=0 to expoz do
  for x:=0 to 416 do HC595($f9);
 end;
shift2;
Write_USB_Device_Buffer(FT_CAM8B,@FT_Out_Buffer,adress);

comread;
adress:=0;
for y:=0 to dy-1+mYn do shift;
clearline;
for y:=0 to mdeltY -1 do
begin
shift;

for x:=0 to apolosa do                 //
    begin
     FT_Out_Buffer[adress]:=dout[3];
     inc(adress,1);
    end;

for x:=0 to dx-1+4*mXn do
begin
 FT_Out_Buffer[adress+0]:=dout[0];
 FT_Out_Buffer[adress+1]:=dout[3];
 inc(adress,2);
end;

if bin = 1 then
 begin

  for x:=0 to 3 do
   begin
    FT_Out_Buffer[adress+0]:=dout[0]+$10;
    FT_Out_Buffer[adress+1]:=dout[1]+$10;
    FT_Out_Buffer[adress+2]:=dout[2]+$10;
    FT_Out_Buffer[adress+3]:=dout[3]+$10;
    inc(adress,4);
   end;
   FT_Out_Buffer[adress+0]:=dout[0]+$10;
   FT_Out_Buffer[adress+1]:=dout[1]+$10;
   FT_Out_Buffer[adress+2]:=dout[2];//+$10;
   FT_Out_Buffer[adress+3]:=dout[3];//+$10;
   inc(adress,4);

 for x:=0 to 4*mdeltX-2 do
  begin
   FT_Out_Buffer[adress+0]:=dout[0];
   FT_Out_Buffer[adress+1]:=dout[1];
   FT_Out_Buffer[adress+2]:=dout[2];
   FT_Out_Buffer[adress+3]:=dout[3];
   inc(adress,4);
  end;
end        else
begin

 for x:=0 to 3 do
  begin
   FT_Out_Buffer[adress+0]:=dout[0]+$10;                           //?????????? ??? ??????, ???? ?????? ?????? RS ?????? ??? ??????? 4 - ?? ???????
   FT_Out_Buffer[adress+1]:=dout[1]+$10;
   FT_Out_Buffer[adress+2]:=dout[2]+$10;
   FT_Out_Buffer[adress+3]:=dout[4]+$10;
   FT_Out_Buffer[adress+4]:=dout[2]+$10;
   FT_Out_Buffer[adress+5]:=dout[4]+$10;
   FT_Out_Buffer[adress+6]:=dout[2]+$10;
   FT_Out_Buffer[adress+7]:=dout[4]+$10;
   FT_Out_Buffer[adress+8]:=dout[2]+$10;
   FT_Out_Buffer[adress+9]:=dout[3]+$10;
   inc(adress,10);
 end;
   FT_Out_Buffer[adress+0]:=dout[0]+$10;                           //?????????? ??? ??????, ???? ?????? ?????? RS ?????? ??? ??????? 4 - ?? ???????
   FT_Out_Buffer[adress+1]:=dout[1]+$10;
   FT_Out_Buffer[adress+2]:=dout[2]+$10;
   FT_Out_Buffer[adress+3]:=dout[4]+$10;
   FT_Out_Buffer[adress+4]:=dout[2]+$10;
   FT_Out_Buffer[adress+5]:=dout[4]+$10;
   FT_Out_Buffer[adress+6]:=dout[2]+$10;
   FT_Out_Buffer[adress+7]:=dout[4]+$10;
   FT_Out_Buffer[adress+8]:=dout[2];
   FT_Out_Buffer[adress+9]:=dout[3];
   inc(adress,10);

 for x:=0 to mdeltX-2 do
  begin
   FT_Out_Buffer[adress+0]:=dout[0];                           //?????????? ??? ??????, ???? ?????? ?????? RS ?????? ??? ??????? 4 - ?? ???????
   FT_Out_Buffer[adress+1]:=dout[1];
   FT_Out_Buffer[adress+2]:=dout[2];
   FT_Out_Buffer[adress+3]:=dout[4];
   FT_Out_Buffer[adress+4]:=dout[2];
   FT_Out_Buffer[adress+5]:=dout[4];
   FT_Out_Buffer[adress+6]:=dout[2];
   FT_Out_Buffer[adress+7]:=dout[4];
   FT_Out_Buffer[adress+8]:=dout[2];
   FT_Out_Buffer[adress+9]:=dout[3];
   inc(adress,10);
  end;
end;

 FT_Out_Buffer[adress+0]:=dout[0];//+$10;
 FT_Out_Buffer[adress+1]:=dout[1];//+$10;
 FT_Out_Buffer[adress+2]:=dout[2]+$10;
 FT_Out_Buffer[adress+3]:=dout[3]+$10;
 inc(adress,4);

for x:=0 to dx2-1+6000-4*mdeltX-4*mXn do
begin
 FT_Out_Buffer[adress+0]:=dout[0];
 FT_Out_Buffer[adress+1]:=dout[3];
 inc(adress,2);
end;
end;
 Write_USB_Device_Buffer(FT_CAM8B,@FT_Out_Buffer,adress);   //������� �� �����!!
end;

{Set camera gain, return bool result}
function CameraSetGain (val : integer) : WordBool; //stdcall; export;
begin
 AD9822(3,val);           //�������� AD9822
 Result :=true;
end;

{Set camera offset, return bool result}
function CameraSetOffset (val : integer) : WordBool; //stdcall; export;
var x : integer;
begin
 x:=abs(2*val);
 if val < 0 then x:=x+256;
 AD9822(6,x);                       //�������� AD9822
 Result :=true;
end;

{Connect camera, return bool result}
{����� ������������ ��������� � ������������� AD9822}
function CameraConnect () : WordBool;  //stdcall; export;
var  FT_flag, FT_OP_flag : boolean;
I : Integer;
begin
 FT_flag:=false;
 GetFTDeviceCount;
 I := FT_Device_Count-1;
 while I >= 0 do
  begin
   GetFTDeviceSerialNo(I);
   if pos('CAM8',FT_Device_String) <> 0 then FT_flag:=true;    //���� ��������� cam81 - ����������
   GetFTDeviceDescription(I);
   Dec(I);
  end;
  if FT_flag then
   begin
    FT_OP_flag:=true;
    if Open_USB_Device_By_Serial_Number(FT_CAM8A,'CAM8A') <> FT_OK then FT_OP_flag := false;
    if Open_USB_Device_By_Serial_Number(FT_CAM8B,'CAM8B')  <> FT_OK then FT_OP_flag := false;
    if Set_USB_Device_BitMode(FT_CAM8B,$ff, $01)  <> FT_OK then FT_OP_flag := false;             // BitMode

    Set_USB_Device_LatencyTimer(FT_CAM8B,2);       //������������ ��������������
    Set_USB_Device_LatencyTimer(FT_CAM8A,2);
    Set_USB_Device_TimeOuts(FT_CAM8A,4000,4000);

    Purge_USB_Device_In(FT_CAM8A);
    Purge_USB_Device_OUT(FT_CAM8A);
    Purge_USB_Device_OUT(FT_CAM8B);

    AD9822(0,$58);             //����� AD9822 - ����� G,2 ������ ���������, CDS �����
    AD9822(1,$a0);             //�������� �������
    AD9822(6,14+256);
    AD9822(3,34);//$3f);       //�������� ��������������� �����. ��� �� ������������� ���
    adress:=0;
    HC595($f9);//($2f);
    Write_USB_Device_Buffer(FT_CAM8B,@FT_Out_Buffer,adress);
   end;
 IsConnected := FT_flag and FT_OP_flag;
 Result := FT_flag and FT_OP_flag;
end;

{Disconnect camera, return bool result}
function CameraDisconnect (): WordBool; //stdcall; export;
var FT_OP_flag : boolean;
begin
 FT_OP_flag := true;
 if Close_USB_Device(FT_CAM8A) <> FT_OK then FT_OP_flag := false;   //�������� ���������
 if Close_USB_Device(FT_CAM8B) <> FT_OK then FT_OP_flag := false;
 IsConnected := not FT_OP_flag;
 Result:= FT_OP_flag;
end;

{Get camera state, return int result}
function CameraGetCameraState : integer;// stdcall; export;
begin
 Result := mCameraState;
end;

procedure ExposureTimerTick; stdcall;
var n : integer;
begin
 KillTimer (0,ExposureTimer);
 KillTimer (0,Timer15V);
 mCameraState := 3;

 adress:=0;
 HC595($f9);                //???????? +15V
 n:=Write_USB_Device_Buffer(FT_CAM8B,@FT_OUT_Buffer,adress);

 readframe (mBin, 1000);

 mImageReady := true;
end;

//????? ??????? ????? ?????? ????????? ??????? +15V
procedure Timer15VTick; stdcall;
var n : integer;
begin
 KillTimer (0,Timer15V);
 adress:=0;
 HC595($79);
 n:=Write_USB_Device_Buffer(FT_CAM8B,@FT_OUT_Buffer,adress);
end;

{Check camera connection, return bool result}
function CameraIsConnected () : WordBool;// stdcall; export;
begin
  Result := IsConnected;
end;

function CameraStartExposure (Bin,StartX,StartY,NumX,NumY : integer; Duration : double; light : WordBool) : WordBool;// stdcall; export;
var n : integer;
begin
 mBin := Bin;             //???????
 if (NumY+StartY > CameraHeight)or(StartY < 0)or(NumY <= 0) then begin mYn:=0;mdeltY:=yccd end
 else begin mYn:=StartY div 2;mdeltY:=NumY div 2 end;
 if (NumX+StartX > CameraWidth)or(StartX < 0)or(NumX <= 0) then begin mXn:=0;mdeltX:=xccd end
 else begin mXn:=StartX div 2;mdeltX:=NumX div 2 end;
 mImageReady := false;
 //camera exposing
 mCameraState := 2;
 if Duration > 0.499 then
 begin
 adress:=0;      // clearwin
 shift3;
 n:=Write_USB_Device_Buffer(FT_CAM8B,@FT_OUT_Buffer,adress);
 ExposureTimer := settimer (0,0,round(Duration*1000-52),@ExposureTimerTick);
 Timer15V := settimer (0,0,1000,@Timer15VTick);
 end                   else
 begin
  mCameraState := 3;
  readframe (mBin,round(Duration*1000));
  mImageReady := true;
 end;

 Result := true;

end;

{Check ImageReady flag, is image ready for transfer - transfer image to driver and return bool ImageReady flag}
function CameraGetImageReady (var frame : camera_image_type) : WordBool;// stdcall; export;
var x,y : integer;
begin
 if (mImageReady) then
 begin
 //camera download ccd
 mCameraState := 4;

    for y := 0 to 2*yccd-1 do
    for x := 0 to 2*xccd-1 do
      frame[x,y] := bufim[x,y];
 //camera idle
 mCameraState := 0;
 end;
 Result := mImageReady;
end;

//????? ?????????? ???????????, ???????????? ???????, ????????? ????????? ?????? ?????

{exports CameraConnect;
exports CameraIsConnected;
exports CameraDisconnect;
exports CameraSetGain;
exports CameraSetOffset;
exports CameraStartExposure;
exports CameraGetCameraState;
exports CameraGetImageReady;

begin}
end.
