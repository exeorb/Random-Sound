Random Sound Plugin
====================

Random Sound Plugin is modified [quakesound plugin](https://forums.alliedmods.net/showthread.php?t=58548)

The main difference are 

* Added new events: `joingame`, `roundendfreeze`, `roundend`
* Plugin can emit sounds randomly from specified folder with the specific pattern

##Instalation##
Merge content with `sourcemod` folder

##Description##
Plugin will create `cfg/rds.cfg` file. There are useful convars for plugin's managment


| ConVar | Description | Type | Default |  
| --- | --- | --- | --- |
| rds_enable | toggle plugin | bool | 1 |  
| rds_volume | volume: should be a number between 0.0. and 1.0 | float | 1.0 |  
| rds_sound_delay | sound delay after event | float | 0.5 |  
| rds_combo_delay | max delay between combos | float | 2.0 |  
| rds_display_time | max time of living menu on the screen | int | 20 |  
| rds_help_enable | toggle help advertisement | bool | 1 |  
| rds_help_delay | max time between help advertisement | float | 30.0 |  

##Usage##

Consider file `configs/rds_list.cfg`

```
"RandomSoundsList"
{
	...

	"event"
	{
		"pattern"	"someword"
		"folder"	"somefolder"
		"config"	"0 or 1 or 2 or 3"
	}
	
	...
}
```

For choosen `event` we have: 

###pattern###

is prefix for searching suitable file by regular expression `someword\w*\.mp3$`

**Notice!**

if pattern is empty i.e. `""`, file will not be found

###folder###

the name of the folder which is in the `sound` directory

**Warning!**

The folder name have to exist otherwise `SetFailState` will be called

###config###

`enum` given below is describing current field

```cpp

enum SoundSetting
{
	NOBODY = 0,
	CLIENT = 1,
	ATTACKER_VICTIM = 2,
	ALL = 3
};


```

**Notice!**


config value of event `joingame` have to be 0 or 1 otherwise sound will not be emitted