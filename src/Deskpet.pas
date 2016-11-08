program DeskPet;
uses SwinGame, sgTypes, sgBackendTypes, sgTimers, sgSprites, SysUtils, Math;

type
	PetState = (Idle, Sleep, Sick, Eating, Upset, Dancing);
	FoodKind = (AppleGood, AppleBad);

	Pet = record
		health: Integer;	
		nextFlipTicks: Integer;
		x, y: Double;
		dx, dy: Double;
		flip: Boolean;	
		animationName: String;	

		state: PetState;
		sprite: Sprite;

		moveTimer: Timer;
		moveFlipTimer: Timer;
		healthTimer: Timer;
		danceTimer: Timer;
		danceFlipTimer: Timer;
	end;

	Food = record
		kind: FoodKind;
		sprite: Sprite;
	end;

	Buttons = record
		sleep: Sprite;
		heal: Sprite;
		feed: Sprite;
	end;

	Game = record
		pet: Pet;
		foods: array of Food;
		buttons: Buttons;
		lowHealthTimer: Timer;

		isPlayingFoodGame: Boolean;
		isDay: Boolean;		

		dayBackground: Bitmap;
		nightBackground: Bitmap;
		border: Bitmap;
		heartFull: Bitmap;
		heartHalf: Bitmap;
		heartEmpty: Bitmap;

		idleMusic: Music;
		sickMusic: Music;
		danceMusic: Music;
		sleepMusic: Music;
		foodMusic: Music;
		currentMusic: ^Music;
	end;

// ============================
// Utility Procedures/Functions
// ============================
function SpriteClicked(const sprite: Sprite): Boolean;
var
	mouseXPos, mouseYPos: Single;
	rect: Rectangle;

begin
	mouseXPos := MouseX(); 
	mouseYPos := MouseY(); 
	rect := SpriteCollisionRectangle(sprite);
	result := false; 

	if MouseClicked(LeftButton) then 
	begin 
		if (mouseXPos >= rect.x) and (mouseXPos <= rect.x + rect.width) 
		and (mouseYPos >= rect.y) and (mouseYPos <= rect.y + rect.height) then 
		begin 
			result := true; 
		end;
	end;
end;

procedure WrapSprite(sprite: Sprite; var x, y: Double);
begin
	if x < -SpriteWidth(sprite) then //offscreen left
		x := ScreenWidth()
	else if x > ScreenWidth() then //offscreen right
		x := -SpriteWidth(sprite);

	if y < -SpriteHeight(sprite) then //offscreen top
		y := ScreenHeight()
	else if y > ScreenHeight() then //offscreen bottom
		y := -SpriteHeight(sprite);
end;

procedure CenterPet(var pet: Pet);
begin
	pet.x := 250;
	pet.y := 160;
end;

// Changed from sgGraphics
procedure DrawSpriteWithOpts(s: Sprite; xOffset, yOffset: Longint; const o: DrawingOptions);
var
	i, idx: Longint;
	angle, scale: Single;
	sp: SpritePtr;
	opts: DrawingOptions;

begin
	opts := o;
	sp := ToSpritePtr(s);

	if not Assigned(sp) then exit;
	
	angle := SpriteRotation(s);
	if angle <> 0 then
	  opts := OptionRotateBmp(angle, sp^.anchorPoint.x - SpriteLayerWidth(s, 0) / 2, sp^.anchorPoint.y  - SpriteLayerHeight(s, 0) / 2, opts);

	scale := SpriteScale(s);
	if scale <> 1 then
	  opts := OptionScaleBmp(scale, scale, opts);

	for i := 0 to High(sp^.visibleLayers) do
	begin
	  idx := sp^.visibleLayers[i];
	  DrawCell(SpriteLayer(s, idx), SpriteCurrentCell(s), 
		Round(sp^.position.x + xOffset + sp^.layerOffsets[idx].x), 
		Round(sp^.position.y + yOffset + sp^.layerOffsets[idx].y),
		opts);
	end;
end;

procedure DrawSpriteWithOpts(s: Sprite; const opts: DrawingOptions);
begin
	DrawSpriteWithOpts(s, 0, 0, opts);
end;

// ==========================
// Setup Procedures/Functions
// ==========================
procedure LoadResources();
begin
	LoadResourceBundleNamed('PetBundle', 'PetBundle.txt', false);

	LoadBitmapNamed('day', 'Day.png');
	LoadBitmapNamed('night', 'Night.png');
	LoadBitmapNamed('border', 'Border.png');

	LoadBitmapNamed('AppleBad','AppleBad.png');
	LoadBitmapNamed('AppleGood', 'AppleGood.png');

	LoadBitmapNamed('SleepIcon','Icon_Sleep.png');
	LoadBitmapNamed('MediIcon', 'Icon_Medi.png');
	LoadBitmapNamed('FeedIcon', 'Icon_Feed.png');

	LoadBitmapNamed('HeartFull','HeartFull.png');
	LoadBitmapNamed('HeartHalf', 'HeartHalf.png');
	LoadBitmapNamed('HeartEmpty', 'HeartEmpty.png');

	LoadSoundEffectNamed('AppleGoodSound', '238283__meroleroman7__8-bit-noise.wav');
	LoadSoundEffectNamed('AppleBadSound', '239987__jalastram__fx114.wav');	
	LoadSoundEffectNamed('GameOver', '333785__projectsu012__8-bit-failure-sound.wav');
end;

procedure SetupButtons(var buttons: Buttons);
begin
	buttons.sleep := CreateSprite(BitmapNamed('SleepIcon'));
	SpriteSetX(buttons.sleep, 300);
	SpriteSetY(buttons.sleep, 20);

	buttons.heal := CreateSprite(BitmapNamed('MediIcon'));
	SpriteSetX(buttons.heal, 350); 
	SpriteSetY(buttons.heal, 20);

	buttons.feed := CreateSprite(BitmapNamed('FeedIcon'));
	SpriteSetX(buttons.feed, 400);
	SpriteSetY(buttons.feed, 20);
end;

procedure SetupPet(var pet: Pet);
begin
	pet.animationName := '';
	pet.state := Idle;
	pet.flip := false;

	pet.sprite := CreateSprite(
		BitmapNamed('Pet'), 
		AnimationScriptNamed('PetAnimations'));

	CenterPet(pet);
	pet.dx := 0;
	pet.dy := 0;

	pet.moveFlipTimer := CreateTimer();
	pet.moveTimer := CreateTimer();
	StartTimer(pet.moveFlipTimer);
	StartTimer(pet.moveTimer);
	pet.nextFlipTicks := 12000;

	pet.health := 10;
	pet.healthTimer := CreateTimer();
	StartTimer(pet.healthTimer);
end;


function SpawnFood(): Food;
begin
	// We're randomly spawning a good or bad apple.
	result.kind := FoodKind(Rnd(2));

	if result.kind = AppleGood then
		result.sprite := CreateSprite(BitmapNamed('AppleGood'))
	else if result.kind = AppleBad then
		result.sprite := CreateSprite(BitmapNamed('AppleBad'));

	// Sets the X cord of an apple, makes sure we spawn the apples within the screens border.
	SpriteSetX(result.sprite, 40 + Rnd(ScreenWidth() - 80 - SpriteWidth(result.sprite)));
	// Sets the Y cord of an apple, we always spawn at the top of the screen. 
	SpriteSetY(result.sprite, 0);
	// We're randomizing the speed of the apples for variety and to avoid too much overlap.
	SpriteSetDY(result.sprite, 1 + Rnd(4));
end;

procedure SetupFoods(var game: Game);
var 
	i: Integer;

begin
	// Sets how many apples we're spawning.
	SetLength(game.foods, 5);

	for i := Low(game.foods) to High(game.foods) do
	begin
		game.foods[i] := SpawnFood();
	end;
end;

procedure SetupGame(var game: Game);
begin
	SetupButtons(game.buttons);
	SetupPet(game.pet);
	SetupFoods(game);

	// Food game variables.
	game.isPlayingFoodGame := false;

	// Day/Night cycle variables.
	game.isDay := true;
	game.dayBackground := BitmapNamed('day');	
	game.nightBackground := BitmapNamed('night');

	// Border.
	game.border := BitmapNamed('border');

	// Heart states.
	game.heartFull := BitmapNamed('HeartFull');
	game.heartHalf := BitmapNamed('HeartHalf');
	game.heartEmpty := BitmapNamed('HeartEmpty');

	// Timer for screen effect when Deskpet is in Sick state.
	game.lowHealthTimer := CreateTimer();
	StartTimer(game.lowHealthTimer);	

	//Music from: https://freesound.org/people/cabled_mess/sounds/335361/
	game.idleMusic := LoadMusic('335361__cabled-mess__little-happy-tune-22-10.wav');	

	//Music from: https://freesound.org/people/Clinthammer/sounds/179510/
	game.sickMusic := LoadMusic('179510__clinthammer__clinthammermusic-gamerstep-chords-2.wav');

	//Music from: https://freesound.org/people/ynef/sounds/352756/
	game.danceMusic := LoadMusic('352756__ynef__trance-beat-with-deep-bassline.wav');

	//Music from: https://freesound.org/people/FoolBoyMedia/sounds/264295/
	game.sleepMusic := LoadMusic('264295__foolboymedia__sky-loop.wav');

	//Music from: https://freesound.org/people/Burinskas/sounds/362133/
	game.foodMusic := LoadMusic('362133__burinskas__chiptune-loop-light.wav');		

end;

// ===========================
// Update Procedures/Functions
// ===========================
function CanSleep(const game: Game): Boolean;
begin
	// Deskpet can Sleep if, isn't Sick, isn't Dancing and we're not playing food game.
	result := (not game.isPlayingFoodGame) and (game.pet.state <> Sick) and (game.pet.state <> Dancing);
end;

function CanHeal(const game: Game): Boolean;
begin
	// Can Heal if Deskpet is Sick, isn't Dancing and we're not playing food game.
	result := (not game.isPlayingFoodGame) and (game.pet.state = Sick) and (game.pet.state <> Dancing);
end;

function CanFoodGame(const game: Game): Boolean;
begin
	// Can play food game if, Deskpet isn't Sick, isn't Sleeping and isn't Dancing.
	result := (game.pet.state <> Sick) and (game.pet.state <> Sleep) and (game.pet.state <> Dancing);
end;

procedure HandleButtons(var game: Game);
begin
	UpdateSprite(game.buttons.sleep);
	UpdateSprite(game.buttons.heal);
	UpdateSprite(game.buttons.feed);

	// Handle Sleep
	if CanSleep(game) and SpriteClicked(game.buttons.sleep) then
	begin
		// Toggles sleep depending on Deskpet state.
		 if game.pet.state = Sleep then
			game.pet.state := Idle
		 else
			game.pet.state := Sleep;
	end;

	// Handle Heal
	if CanHeal(game) and SpriteClicked(game.buttons.heal) then
	begin
		// Sets Deskpet to Idle with 4 hp, 
		// Resets the timer so we don't immediately start dropping hp.
		 game.pet.state := Idle;
		 game.pet.health := 4;
		 ResetTimer(game.pet.healthTimer);
	end;

	// Handle Food
	if CanFoodGame(game) and SpriteClicked(game.buttons.feed) then
	begin
		// Toggles food game. 
		game.isPlayingFoodGame := not game.isPlayingFoodGame;
	end;
end;

procedure UpdateDay(var game: Game);
var
	currTime: TDateTime;
	hh,mm,ss,ms: Word;

begin
	currTime := Now;
	DecodeTime(currTime, hh, mm, ss, ms);
	// The background will change depending on the computers time.
	// From 7am to 5pm it will be set to Day 6pm to 6am is Night.
	if (hh >= 7) and (hh <= 17) then
		game.isDay := true
	else
		game.isDay := false;
end;

procedure HandleFoodsClicked(var game: Game);
var
	i: Integer;
begin
	for i := Low(game.foods) to High(game.foods) do
	begin
		if SpriteClicked(game.foods[i].sprite) 
			and (game.foods[i].kind = AppleGood) then
		begin
			// AppleGood = +1 hp
			game.pet.health += 1;
			PlaySoundEffect('AppleGoodSound');
			// If an apple is clicked it spawns a new one
			game.foods[i] := SpawnFood();
		end
		else if SpriteClicked(game.foods[i].sprite)
			and (game.foods[i].kind = AppleBad) then
		begin
			// AppleBad = -1 hp
			game.pet.health -= 1;
			PlaySoundEffect('AppleBadSound');
			game.foods[i] := SpawnFood();
		end;
	end;
end;

procedure UpdateFoods(var foods: array of Food);
var
	i: Integer;
begin
	for i := Low(foods) to High(foods) do
	begin
		UpdateSprite(foods[i].sprite);
		// If an apple has moved off the screen spawn a new apple.
		if(SpriteY(foods[i].sprite) > ScreenHeight()) then
			foods[i] := SpawnFood();
	end;
end;

procedure UpdateFoodGame(var game: Game);
begin
	// If we're playing food game but Deskpets hp reaches 0,
	// kick us back to the main screen and play the Gameover SFX.
	if (game.pet.health = 0) and (game.isPlayingFoodGame) then
	begin
		game.isPlayingFoodGame := false;
		PlaySoundEffect('GameOver');
		Delay(1000);
	end;
	// If we're playing the food game, 
	// Deskpet should be in the Eating state.
	if game.isPlayingFoodGame = true then
	begin
		game.pet.state := Eating;

		HandleFoodsClicked(game);
		UpdateFoods(game.foods);
	end
	else if game.pet.state = Eating then
	begin
		// Deskpet is in the Eating state but the game has ended, 
		// Go back to Idle state.
		game.pet.state := Idle;
	end;
end;

procedure UpdatePetHealth(var pet: Pet);
begin

	// Deskpets health should go down by 1hp every 10 secs.
	if TimerTicks(pet.healthTimer) > 10000 then
	begin
		ResetTimer(pet.healthTimer);

		// Deskpet doesn't lose hp when eating, sleeping or dancing.
		if (pet.state = Eating) or (pet.state = Sleep) or (pet.state = Dancing) then
			Exit;

		pet.health -= 1;
	end;

	// Deskpets hp should never go below 0.
	pet.health := Max(pet.health, 0);

	// Deskpets hp should never go above 10.
	pet.health := Min(pet.health, 10);
end;

procedure UpdatePetState(var pet: Pet);
begin
	// Eating state takes priority, that means we're
	// playing the food game which should handle
	// the state transition itself.
	if pet.state = Eating then 
		Exit;

	// If DeskPet is sleeping then we suspend other states.
	if pet.state = Sleep then
		Exit;

	// If DeskPet is dancing then we suspend other states.
	if pet.state = Dancing then
		Exit;

	// If DeskPets health is at 0 it's sick.
	if pet.health = 0 then
		pet.state := Sick
	// If DeskPets health is <= 3 it's sad
	else if pet.health <= 3 then
		pet.state := Upset
	else
		pet.state := Idle;
end;

procedure UpdateMusic(var game: Game);
var
	newMusic: ^Music;

begin
	// The music will change depending on what state DeskPets in.
	newMusic := nil;

	if game.pet.state = Idle then
		newMusic := @game.idleMusic;

	if (game.pet.state = Sick) or (game.pet.state = Upset) then
		newMusic := @game.sickMusic;	

	if game.pet.state = Dancing then
		newMusic := @game.danceMusic;

	if game.pet.state = Sleep then
		newMusic := @game.sleepMusic;

	if game.pet.state = Eating then
		newMusic := @game.foodMusic;	

	if newMusic = nil then
		StopMusic()
	else if (not MusicPlaying()) or (MusicFilename(newMusic^) <> MusicFilename(game.currentMusic^)) then
	begin
		game.currentMusic := newMusic;
		PlayMusic(game.currentMusic^);
	end;
end;

procedure UpdatePetDance(var pet: Pet);
begin
	// If Deskpets clicked, start dancing!
	if (pet.state = Idle) and SpriteClicked(pet.sprite) then
	begin
		pet.state := Dancing;
		pet.danceTimer := CreateTimer();
		pet.danceFlipTimer := CreateTimer();

		StartTimer(pet.danceTimer);
		StartTimer(pet.danceFlipTimer);
	end;

	if (pet.state = Dancing) and (TimerTicks(pet.danceFlipTimer) > 200) then
	begin
		ResetTimer(pet.danceFlipTimer);

		pet.flip := not pet.flip;
	end;

	// If our dance timer has finished, back to Idle.
	if (pet.state = Dancing) and (TimerTicks(pet.danceTimer) > 2000) then
	begin
		StopTimer(pet.danceTimer);	
		StopTimer(pet.danceFlipTimer);

		pet.flip := false;
		pet.state := Idle;
	end;
end;

procedure UpdatePetMove(var pet: Pet);
begin
	// We want to move around if we're Idle.
	// We use a timer to delay it which makes it
	// look more like a retro game.
	if pet.state = Idle then
	begin
		if TimerTicks(pet.moveTimer) > 200 then
		begin
			ResetTimer(pet.moveTimer);

			if TimerTicks(pet.moveFlipTimer) > pet.nextFlipTicks then
			begin
				ResetTimer(pet.moveFlipTimer);

				pet.flip := not pet.flip;
				pet.nextFlipTicks := 3000 + Rnd(12000);
			end;

			// Makes Deskpet not walk off the screen
			if (pet.x < 0) or ((pet.x + SpriteWidth(pet.sprite)) > ScreenWidth()) then
				pet.flip := not pet.flip;

			if pet.flip then
				pet.dx := 5
			else
				pet.dx := -5;

			// Makes Deskpet hop between +10 and -10
			if pet.dy = 10 then
				pet.dy := -10
			else 
				pet.dy := 10;

			pet.x += pet.dx;
			pet.y += pet.dy;

			// Wrap Deskpet if it goes offscreen
			// This is left in for future minigames.
			WrapSprite(pet.sprite, pet.x, pet.y);
		end;
	end
	else
	begin
		// In other states we want to center the pet.
		pet.dx := 0;
		pet.dy := 0;
		CenterPet(pet);
	end;

	SpriteSetX(pet.sprite, pet.x);
	SpriteSetY(pet.sprite, pet.y);
end;

procedure UpdatePetSprite(var pet: Pet);
var 
	newAnimation: String;

begin
	case pet.state of
		Idle: newAnimation := 'Idle';
		Sleep: newAnimation := 'Sleep';
		Sick: newAnimation := 'Sick';
		Eating: newAnimation := 'Eating';
		Upset: newAnimation := 'Upset';
		Dancing: newAnimation := 'Dancing';
	end;

	// We only want to start an animation
	// if we're changing from our current animation. 
	if pet.animationName <> newAnimation then
	begin
		pet.animationName := newAnimation;
		SpriteStartAnimation(pet.sprite, newAnimation);
	end;

	UpdateSprite(pet.sprite);
end;

procedure UpdatePet(var pet: Pet);
begin
	UpdatePetHealth(pet);
	UpdatePetState(pet);
	UpdatePetDance(pet);
	UpdatePetMove(pet);
	UpdatePetSprite(pet);
end;

procedure UpdateGame(var game: Game);
begin
	HandleButtons(game);
	UpdateDay(game);
	UpdateFoodGame(game);
	UpdatePet(game.pet);
	UpdateMusic(game);
end;

// ===============
// Draw Procedures
// ===============
procedure DrawBackground(const game: Game);
begin
	if game.isDay = true then
		DrawBitmap(game.dayBackground, 0, 0, OptionFlipY())
	else
		DrawBitmap(game.nightBackground, 0, 0);
end;

procedure DrawPet(const pet: Pet);
begin
	if pet.flip then
		DrawSpriteWithOpts(pet.Sprite, OptionFlipY())
	else
		DrawSprite(pet.Sprite);
end;

procedure DrawLight(const game: Game);
begin
	// The background dims.
	if game.pet.state = Sleep then
		FillRectangle(RGBAColor(0, 0, 0, 125), 0, 0, ScreenWidth(), ScreenHeight());
	// The background raves between a random colours.
	if game.pet.state = Dancing then
		FillRectangle(RGBAColor(Rnd(255), Rnd(255), Rnd(255), 125), 0, 0, ScreenWidth(), ScreenHeight());
	// The background flicks between 2 red hues for an emergency effect.
	if game.pet.state = Sick then
	begin
		if TimerTicks(game.lowHealthTimer) < 600 then
			FillRectangle(RGBAColor(100, 0, 0, 125), 0, 0, ScreenWidth(), ScreenHeight());

		if (TimerTicks(game.lowHealthTimer) >= 600) and (TimerTicks(game.lowHealthTimer) <= 1000) then
			FillRectangle(RGBAColor(200, 0, 0, 125), 0, 0, ScreenWidth(), ScreenHeight());

		if TimerTicks(game.lowHealthTimer) >= 1000 then
		begin
			FillRectangle(RGBAColor(200, 0, 0, 125), 0, 0, ScreenWidth(), ScreenHeight());
			ResetTimer(game.lowHealthTimer);
		end;
	end;
end;

procedure DrawFoods(const game: Game);
var
	i: Integer;

begin
	if game.isPlayingFoodGame then
	begin
		for i := Low(game.foods) to High(game.foods) do
		begin
			DrawSprite(game.foods[i].sprite);
		end;
	end;
end;

procedure DrawBorder(const game: Game);
begin
	DrawBitmap(game.border, 0, 0);
end;

procedure DrawButtons(const game: Game);
begin
	DrawSprite(game.buttons.sleep);
	// Draws a black semi-transparent rectangle over the button if it cannot be clicked.
	if not CanSleep(game) then
		FillRectangle(RGBAColor(0, 0, 0, 125), SpriteCollisionRectangle(game.buttons.sleep));

	DrawSprite(game.buttons.heal);
	if not CanHeal(game) then
		FillRectangle(RGBAColor(0, 0, 0, 125), SpriteCollisionRectangle(game.buttons.heal));

	DrawSprite(game.buttons.feed);
	if not CanFoodGame(game) then
		FillRectangle(RGBAColor(0, 0, 0, 125), SpriteCollisionRectangle(game.buttons.feed));
end;

procedure DrawHealth(const game: Game);
var
	i: Integer;
	x, y: Single;
	bmp: Bitmap;

begin
	for i := 0 to 4 do
	begin
		//  i |     0     |     1     |     2     |     3     |     4
		// ---+-----------+-----------+-----------+-----------+------------
		//  h | [0, 1, 2] | [2, 3, 4] | [4, 5, 6] | [6, 7, 8] | [8, 9, 10]
		//  x | 0 + 10    | 45 + 10   | 90 + 10   | 135 + 10  | 180 + 10 
		//  y | 10        | 5         | 10        | 5         | 10    

		// Start 10 away from border,
		// 45 units between hearts.
		x := (i * 45) + 10;
		// If i is even y = 10, if i is odd y = 5
		y := 10 - (5 * (i Mod 2));

		if game.pet.health <= (i * 2) then
			bmp := game.heartEmpty
		else if game.pet.health = (i * 2) + 1 then
			bmp := game.heartHalf
		else if game.pet.health >= (i * 2) + 2 then
			bmp := game.heartFull;

		DrawBitmap(bmp, x, y);
	end;
end;

procedure DrawGame(const game: Game);
begin
	DrawBackground(game);
	DrawPet(game.pet);
	DrawLight(game);
	DrawFoods(game);
	DrawBorder(game);
	DrawButtons(game);
	DrawHealth(game);
end;

procedure TerminalInstructions();
begin
	WriteLn('+-----Instructions------+');
	WriteLn('|                       |');
	WriteLn('| Deskpet <3s Red Apples|');
	WriteLn('|                       |');	
	WriteLn('|  If Deskpet is Sick   |');
	WriteLn('| you cant Play anymore |');
	WriteLn('|                       |');	
	WriteLn('| If Deskpet hits 0 hp  |');
	WriteLn('|  during food game =   |');
	WriteLn('|       GAMEOVER        |');
	WriteLn('|                       |');		
	WriteLn('|Click Deskpet to Dance!|');
	WriteLn('+-----------------------+');										
end;

// =========
// Game Loop
// =========
procedure Main();
var
	myGame: Game;

begin
	OpenGraphicsWindow('DeskPet', 476, 299);
	LoadResources();
	SetupGame(myGame);

	TerminalInstructions();

	repeat
		ProcessEvents();
		ClearScreen(ColorWhite);
		UpdateGame(myGame);	
		DrawGame(myGame);
		RefreshScreen(60);
	until WindowCloseRequested();
end;

begin
	Main();
end.