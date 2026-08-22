package com.riseup.dailytracker

import android.app.*
import android.content.*
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.*
import android.provider.Settings
import android.net.Uri
import org.json.JSONObject
import java.util.Calendar

private const val PREF = "riseup45.alarms"
private const val KEY = "tasks"
private const val DONE = "completed"
private const val ID = "taskId"
private const val TITLE = "taskTitle"
private const val REMINDER = "com.riseup.dailytracker.REMINDER"
private const val ALARM = "com.riseup.dailytracker.ALARM"
private const val ACTION_DONE = "com.riseup.dailytracker.DONE"
private const val ACTION_SNOOZE = "com.riseup.dailytracker.SNOOZE"

data class RiseUpAlarm(val id:String, val title:String, val reminderAt:Long, val alarmAt:Long, val recurrence:String) {
  val at: Long get() = alarmAt
}

object RiseUpAlarmScheduler {
  fun exact(context: Context): Boolean {
    val manager = context.getSystemService(AlarmManager::class.java)
    return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
  }
  fun requestExact(context: Context): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !exact(context)) {
      context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
        data = Uri.parse("package:${context.packageName}"); addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      })
    }
    return exact(context)
  }
  fun schedule(context: Context, item: RiseUpAlarm): Boolean {
    cancelPending(context, item.id); val all = read(context); all[item.id] = item; write(context, all)
    schedulePair(context, item); return exact(context)
  }
  fun cancel(context: Context, id:String) { cancelPending(context,id); context.stopService(Intent(context, AlarmSoundService::class.java)); val all=read(context); all.remove(id); write(context,all) }
  fun cancelAll(context: Context) { read(context).keys.toList().forEach { cancelPending(context,it) }; context.stopService(Intent(context, AlarmSoundService::class.java)); write(context, mutableMapOf()) }
  fun restore(context: Context) {
    val now=System.currentTimeMillis()
    read(context).values.toList().forEach { old ->
      var item=old
      while(item.alarmAt <= now && item.recurrence != "none") { val nextAlarmAt=next(item.alarmAt,item.recurrence); item=item.copy(reminderAt=nextAlarmAt-300000, alarmAt=nextAlarmAt) }
      if(item.alarmAt <= now) cancel(context,item.id) else { val all=read(context); all[item.id]=item; write(context,all); cancelPending(context,item.id); schedulePair(context,item) }
    }
  }
  fun fired(context: Context, id:String) {
    val item=read(context)[id] ?: return
    if(item.recurrence == "none") { val all=read(context);all.remove(id);write(context,all) }
    else { val nextAlarmAt=next(item.alarmAt,item.recurrence); val next=item.copy(reminderAt=nextAlarmAt-300000, alarmAt=nextAlarmAt); val all=read(context);all[id]=next;write(context,all);schedulePair(context,next) }

  }
  fun snooze(context: Context,id:String,title:String) = set(context,System.currentTimeMillis()+300000,alarmIntent(context,id,title,true))
  fun done(context: Context,id:String) { cancel(context,id); val p=context.getSharedPreferences(PREF,0); p.edit().putStringSet(DONE,(p.getStringSet(DONE,emptySet())!! + id)).apply() }
  fun consumeDone(context: Context):List<String> { val p=context.getSharedPreferences(PREF,0);val r=p.getStringSet(DONE,emptySet())!!.toList();p.edit().remove(DONE).apply();return r }
  private fun schedulePair(c:Context,x:RiseUpAlarm) { set(c,x.alarmAt,alarmIntent(c,x.id,x.title,false)); if(x.reminderAt > System.currentTimeMillis()) set(c,x.reminderAt,reminderIntent(c,x.id,x.title)) }
  private fun set(c:Context,at:Long,p:PendingIntent) { val m=c.getSystemService(AlarmManager::class.java); if(Build.VERSION.SDK_INT>=23) { if(exact(c)) m.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,p) else m.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,p) } else m.setExact(AlarmManager.RTC_WAKEUP,at,p) }
  private fun cancelPending(c:Context,id:String) { val m=c.getSystemService(AlarmManager::class.java);m.cancel(alarmIntent(c,id,"",false));m.cancel(alarmIntent(c,id,"",true));m.cancel(reminderIntent(c,id,"")) }
  private fun alarmIntent(c:Context,id:String,title:String,snooze:Boolean):PendingIntent { val i=Intent(c,TaskAlarmReceiver::class.java).apply { action=ALARM;putExtra(ID,id);putExtra(TITLE,title) };return PendingIntent.getBroadcast(c,id.hashCode() xor if(snooze) 0x22 else 0x44,i,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
  private fun reminderIntent(c:Context,id:String,title:String):PendingIntent { val i=Intent(c,TaskReminderReceiver::class.java).apply { action=REMINDER;putExtra(ID,id);putExtra(TITLE,title) };return PendingIntent.getBroadcast(c,id.hashCode() xor 0x66,i,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
  private fun next(at:Long,r:String):Long { val c=Calendar.getInstance().apply{timeInMillis=at}; when(r) {"daily"->c.add(Calendar.DATE,1);"weekly"->c.add(Calendar.DATE,7);"weekdays"->do { c.add(Calendar.DATE,1) } while(c.get(Calendar.DAY_OF_WEEK)==Calendar.SATURDAY||c.get(Calendar.DAY_OF_WEEK)==Calendar.SUNDAY) };return c.timeInMillis }
  private fun read(c:Context):MutableMap<String,RiseUpAlarm> { val j=JSONObject(c.getSharedPreferences(PREF,0).getString(KEY,"{}"));val r=mutableMapOf<String,RiseUpAlarm>();j.keys().forEach { id-> val x=j.getJSONObject(id);val alarmAt=if(x.has("alarmAt")) x.getLong("alarmAt") else x.getLong("at");r[id]=RiseUpAlarm(id,x.getString("title"),x.optLong("reminderAt",alarmAt-300000),alarmAt,x.optString("recurrence","none")) };return r }
  private fun write(c:Context,all:MutableMap<String,RiseUpAlarm>) { val j=JSONObject();all.values.forEach{x->j.put(x.id,JSONObject().put("title",x.title).put("reminderAt",x.reminderAt).put("alarmAt",x.alarmAt).put("recurrence",x.recurrence))};c.getSharedPreferences(PREF,0).edit().putString(KEY,j.toString()).apply() }
}
object RiseUpNotifications {
  const val alarmChannelId="riseup_native_alarm"
  private const val reminderChannelId="riseup_native_reminder"
  fun fullScreenAllowed(c:Context):Boolean = Build.VERSION.SDK_INT < 34 || c.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
  fun alarmChannel(c:Context) { if(Build.VERSION.SDK_INT>=26) c.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(alarmChannelId,"Task alarms",NotificationManager.IMPORTANCE_HIGH).apply { lockscreenVisibility=Notification.VISIBILITY_PUBLIC;enableVibration(true) }) }
  fun reminder(c:Context,id:String,title:String,text:String) { if(Build.VERSION.SDK_INT>=26) c.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(reminderChannelId,"Task reminders",NotificationManager.IMPORTANCE_DEFAULT).apply { enableVibration(true) });c.getSystemService(NotificationManager::class.java).notify(id.hashCode(),Notification.Builder(c,reminderChannelId).setSmallIcon(R.drawable.ic_notification).setContentTitle(title).setContentText(text).setAutoCancel(true).build()) }
}
class TaskReminderReceiver:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){val id=i.getStringExtra(ID)?:return;val t=i.getStringExtra(TITLE)?:"your task";RiseUpNotifications.reminder(c,id,"Upcoming Task","Your task \"$t\" starts in 5 minutes.")}}
class TaskAlarmReceiver:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){if(i.action!=ALARM)return;val id=i.getStringExtra(ID)?:return;val title=i.getStringExtra(TITLE)?:"Task";RiseUpAlarmScheduler.fired(c,id);AlarmSoundService.start(c,id,title)}}
class AlarmActionReceiver:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){val id=i.getStringExtra(ID)?:return;val title=i.getStringExtra(TITLE)?:"Task";c.stopService(Intent(c,AlarmSoundService::class.java));if(i.action==ACTION_DONE)RiseUpAlarmScheduler.done(c,id) else if(i.action==ACTION_SNOOZE)RiseUpAlarmScheduler.snooze(c,id,title)}}
class AlarmBootReceiver:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){RiseUpAlarmScheduler.restore(c)}}
class AlarmSoundService:Service(){
  private var ringtone:Ringtone?=null;private var vibrator:Vibrator?=null
  companion object { fun start(c:Context,id:String,title:String){val i=Intent(c,AlarmSoundService::class.java).apply{putExtra(ID,id);putExtra(TITLE,title)};if(Build.VERSION.SDK_INT>=26)c.startForegroundService(i) else c.startService(i)} }
  override fun onStartCommand(i:Intent?,f:Int,s:Int):Int {val id=i?.getStringExtra(ID)?:return START_NOT_STICKY;val title=i.getStringExtra(TITLE)?:"Task";RiseUpNotifications.alarmChannel(this);startForeground(45102,notification(id,title));ringtone=RingtoneManager.getRingtone(this,RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM));ringtone?.play();vibrator=getSystemService(VIBRATOR_SERVICE) as Vibrator;if(Build.VERSION.SDK_INT>=26)vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0,500,400),0));else @Suppress("DEPRECATION") vibrator?.vibrate(longArrayOf(0,500,400),0);return START_NOT_STICKY}
  private fun notification(id:String,title:String):Notification {val open=PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);fun action(name:String,code:Int):PendingIntent {val i=Intent(this,AlarmActionReceiver::class.java).apply{action=name;putExtra(ID,id);putExtra(TITLE,title)};return PendingIntent.getBroadcast(this,id.hashCode()xor code,i,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)};val builder=Notification.Builder(this,RiseUpNotifications.alarmChannelId).setSmallIcon(R.drawable.ic_notification).setContentTitle("TASK TIME").setContentText(title).setCategory(Notification.CATEGORY_ALARM).setVisibility(Notification.VISIBILITY_PUBLIC).setOngoing(true).setContentIntent(open).addAction(R.drawable.ic_notification,"DONE",action(ACTION_DONE,1)).addAction(R.drawable.ic_notification,"SNOOZE",action(ACTION_SNOOZE,2));if(RiseUpNotifications.fullScreenAllowed(this)) builder.setFullScreenIntent(open,true);return builder.build()}
  override fun onDestroy(){ringtone?.stop();vibrator?.cancel();super.onDestroy()};override fun onBind(i:Intent?):IBinder?=null
}