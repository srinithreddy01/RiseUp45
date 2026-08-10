import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  BarChart3, Bell, BookOpen, CalendarDays, Check, CheckCircle2,
  ChevronRight, Circle, Clock3, Code2, Dumbbell, Ellipsis, Flame, Home,
  Camera, LogOut, MoreHorizontal, Plus, Settings, Target, Trash2, Trophy, UserPlus, UserRound, X, Zap
} from 'lucide-react'
import './App.css'
import { workoutForDate } from './data/workoutSchedule'
import { dateKey, formatDate, getStreak, makeId, nextOccurrence, startOfWeek } from './utils/productivity'

const categories = ['Personal', 'College', 'Coding', 'Fitness', 'Learning', 'Other']
const nav = [
  ['home', 'Home', Home], ['tasks', 'Tasks', CheckCircle2], ['gym', 'Gym', Dumbbell],
  ['learning', 'Learning', Code2], ['progress', 'Progress', BarChart3], ['settings', 'Settings', Settings]
]

const defaultLearning = { cards: [], dates: {} }
const blankTask = () => ({ title: '', category: 'Personal', priority: 'Medium', dueDate: dateKey(), time: '', notes: '', recurrence: 'None' })
const blankLearningCard = () => ({ title: '', description: '', unit: 'problems solved', color: '#3f6de0', short: '' })
const defaultSettings = { theme: 'light', defaultReminder: '18:00', notifications: false, alarm: true, gymAlarm: true, gymAlarmTime: '16:30' }
const storagePrefix = 'riseup'
const legacyStoragePrefix = 'stride'

function App() {
  const [storedUsers, setUsers] = useStoredState(`${storagePrefix}.users`, [], `${legacyStoragePrefix}.users`)
  const [activeUserId, setActiveUserId] = useStoredState(`${storagePrefix}.active-user`, '', `${legacyStoragePrefix}.active-user`)
  const users = Array.isArray(storedUsers) ? storedUsers.filter(item => item && typeof item.id === 'string' && typeof item.username === 'string').map(item => ({ ...item, name: typeof item.name === 'string' && item.name.trim() ? item.name : item.username, photo: typeof item.photo === 'string' ? item.photo : '' })) : []
  const user = users.find(item => item.id === activeUserId)
  const createUser = ({ name, username }) => {
    const cleanUsername = username.trim().replace(/^@+/, '')
    if (!cleanUsername || users.some(item => item.username.toLowerCase() === cleanUsername.toLowerCase())) return false
    const nextUser = { id: makeId(), name: name.trim() || cleanUsername, username: cleanUsername, photo: '', createdAt: new Date().toISOString(), legacyDataOwner: users.length === 0 }
    setUsers(current => [...(Array.isArray(current) ? current : []), nextUser]); setActiveUserId(nextUser.id); return true
  }
  const updateUser = changes => setUsers(current => (Array.isArray(current) ? current : []).map(item => item.id === activeUserId ? { ...item, ...changes } : item))
  if (!user) return <AccountScreen users={users} onChoose={setActiveUserId} onCreate={createUser}/>
  return <Workspace user={user} users={users} updateUser={updateUser} onSwitchUser={() => setActiveUserId('')}/>
}

function Workspace({ user, users, updateUser, onSwitchUser }) {
  const [tasks, setTasks] = useUserStoredState(user, 'tasks', [])
  const [learning, setLearning] = useUserStoredState(user, 'learning', defaultLearning)
  const [gym, setGym] = useUserStoredState(user, 'gym', {})
  const [dailyHistory, setDailyHistory] = useUserStoredState(user, 'daily-history', {})
  const [settings, setSettings] = useUserStoredState(user, 'settings', defaultSettings)
  const [page, setPage] = useState('home')
  const [form, setForm] = useState(null)
  const [menuTask, setMenuTask] = useState(null)
  const [editingProfile, setEditingProfile] = useState(false)
  const [toast, setToast] = useState('')
  const reminded = useRef(new Set())
  const gymAlarmed = useRef(new Set())
  const audioContext = useRef(null)
  const today = dateKey()
  const toggleTask = useCallback(id => setTasks(all => {
    const target = all.find(t => t.id === id)
    if (!target) return all
    const next = all.map(t => t.id === id ? { ...t, completed: !t.completed } : t)
    if (!target.completed && target.recurrence && target.recurrence !== 'None') {
      const dueDate = nextOccurrence(target.dueDate, target.recurrence)
      if (!all.some(t => t.title === target.title && t.dueDate === dueDate)) next.push({ ...target, id: makeId(), dueDate, completed: false, createdAt: today })
    }
    return next
  }), [setTasks, today])

  useEffect(() => {
    const resolved = settings.theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : settings.theme
    document.documentElement.dataset.theme = resolved
  }, [settings.theme])
  useEffect(() => {
    if (settings.gymAlarmTime === '04:30') setSettings(current => ({ ...current, gymAlarmTime: '16:30' }))
  }, [settings.gymAlarmTime, setSettings])
  const playAlarm = useCallback(() => {
    if (!settings.alarm || !window.AudioContext) return
    const context = audioContext.current || new window.AudioContext()
    audioContext.current = context
    if (context.state === 'suspended') context.resume()
    const oscillator = context.createOscillator(); const gain = context.createGain()
    oscillator.connect(gain); gain.connect(context.destination); oscillator.frequency.value = 880; gain.gain.setValueAtTime(.04, context.currentTime)
    oscillator.start(); oscillator.stop(context.currentTime + .35)
  }, [settings.alarm])
  useEffect(() => {
    setTasks(old => old.filter(task => !task.id.startsWith('welcome-')))
  }, [setTasks])
  useEffect(() => {
    const saveSnapshot = key => setDailyHistory(old => old[key] ? old : { ...old, [key]: makeDailySnapshot(key, tasks, gym, learning) })
    const recordDayBoundary = () => {
      const current = dateKey(); const active = localStorage.getItem(userStorageKey(user.id, 'active-day'))
      if (active && active !== current) {
        saveSnapshot(active)
        // Keep unfinished work visible tomorrow so it can be continued.
        setTasks(old => old.map(task => !task.completed && task.dueDate === active ? { ...task, dueDate: current, carriedForward: true } : task))
      }
      localStorage.setItem(userStorageKey(user.id, 'active-day'), current)
      const time = new Date()
      if (time.getHours() === 23 && time.getMinutes() >= 59) saveSnapshot(current)
    }
    recordDayBoundary()
    const id = setInterval(recordDayBoundary, 30000)
    return () => clearInterval(id)
  }, [tasks, gym, learning, setDailyHistory, setTasks, user.id])
  useEffect(() => {
    if (!settings.notifications || !('Notification' in window)) return
    const check = async () => {
      const timeNow = new Date().toTimeString().slice(0, 5)
      for (const task of tasks.filter(t => !t.completed && t.dueDate === dateKey() && t.time && t.time <= timeNow)) {
        const key = `${dateKey()}-${task.id}`
        if (reminded.current.has(key)) continue
        reminded.current.add(key); playAlarm()
        const options = { body: task.title, tag: key, data: { taskId: task.id }, actions: [{ action: 'complete', title: 'Complete' }, { action: 'snooze', title: 'Snooze 10 min' }, { action: 'reschedule', title: 'Reschedule' }] }
        try { const registration = await navigator.serviceWorker?.ready; if (registration) await registration.showNotification('Task reminder', options); else new Notification('Task reminder', options) } catch { new Notification('Task reminder', { body: task.title }) }
      }
    }
    check(); const id = setInterval(check, 30000)
    return () => clearInterval(id)
  }, [settings.notifications, tasks, settings.alarm, playAlarm])
  useEffect(() => {
    if (!settings.notifications || settings.gymAlarm === false || !('Notification' in window)) return
    const checkGymAlarm = async () => {
      const now = new Date(); const key = dateKey(); const alarmTime = settings.gymAlarmTime || '16:30'
      if (now.toTimeString().slice(0, 5) < alarmTime || gymAlarmed.current.has(key)) return
      gymAlarmed.current.add(key); playAlarm()
      const options = { body: 'It is 4:30 PM â€” time to get ready for your workout.', tag: `gym-alarm-${key}`, data: { type: 'gym-alarm' } }
      try { const registration = await navigator.serviceWorker?.ready; if (registration) await registration.showNotification('ðŸ‹ï¸ Time to go GYM!', options); else new Notification('ðŸ‹ï¸ Time to go GYM!', options) } catch { new Notification('ðŸ‹ï¸ Time to go GYM!', { body: options.body }) }
    }
    checkGymAlarm(); const id = setInterval(checkGymAlarm, 30000)
    return () => clearInterval(id)
  }, [settings.notifications, settings.gymAlarm, settings.gymAlarmTime, playAlarm])
  const todayTasks = tasks.filter(t => t.dueDate === today)
  const completed = todayTasks.filter(t => t.completed).length
  const percent = todayTasks.length ? Math.round((completed / todayTasks.length) * 100) : 0
  const week = useMemo(() => weeklyData(tasks), [tasks])
  const streak = getStreak(tasks)
  const workout = workoutForDate(new Date())
  const gymDone = Boolean(gym[today])
  // Learning cards and their totals never reset; only the per-day log starts at zero.
  const todayLearn = learning.dates?.[today] || {}

  const notify = text => { setToast(text); setTimeout(() => setToast(''), 2600) }
  useEffect(() => {
    if (!navigator.serviceWorker) return
    const handleAction = event => {
      const { action, taskId } = event.data || {}; const task = tasks.find(item => item.id === taskId)
      if (!task) return
      if (action === 'complete') toggleTask(taskId)
      if (action === 'snooze') setTasks(all => all.map(item => item.id === taskId ? { ...item, time: addMinutes(item.time, 10) } : item))
      if (action === 'reschedule') { setPage('tasks'); setForm(task) }
    }
    navigator.serviceWorker.addEventListener('message', handleAction)
    return () => navigator.serviceWorker.removeEventListener('message', handleAction)
  }, [tasks, setTasks, toggleTask])
  const removeTask = id => { setTasks(all => all.filter(t => t.id !== id)); setMenuTask(null); notify('Task deleted') }
  const saveTask = item => {
    if (!item.title.trim()) return
    setTasks(all => item.id ? all.map(t => t.id === item.id ? item : t) : [...all, { ...item, id: makeId(), completed: false, createdAt: today }])
    setForm(null); notify(item.id ? 'Task updated' : 'Task added for today')
  }
  const updateLearning = (id, amount) => {
    const value = Math.max(0, amount)
    setLearning(old => { const previous = old.dates?.[today]?.[id] || 0; return { ...old, cards: (old.cards || []).map(card => card.id === id ? { ...card, total: Math.max(0, card.total + value - previous) } : card), dates: { ...old.dates, [today]: { ...(old.dates?.[today] || {}), [id]: value } } } })
  }
  const saveLearningCard = card => setLearning(old => ({ ...old, cards: card.id ? (old.cards || []).map(item => item.id === card.id ? card : item) : [...(old.cards || []), { ...card, id: makeId(), total: 0 }] }))
  const deleteLearningCard = id => { if (!window.confirm('Delete this learning card and its logged totals?')) return; setLearning(old => ({ ...old, cards: (old.cards || []).filter(card => card.id !== id), dates: Object.fromEntries(Object.entries(old.dates || {}).map(([day, values]) => [day, Object.fromEntries(Object.entries(values).filter(([key]) => key !== id))])) })); notify('Learning card deleted') }
  const toggleGym = () => { setGym(old => ({ ...old, [today]: !old[today] })); notify(gymDone ? 'Workout moved back to pending' : 'Workout complete â€” great work!') }
  const selectPage = value => { setPage(value); window.scrollTo({ top: 0, behavior: 'smooth' }) }

  const shared = { tasks, setTasks, gym, setGym, dailyHistory, todayTasks, completed, percent, streak, week, workout, gymDone, learning, setLearning, todayLearn, toggleTask, removeTask, setForm, setMenuTask, menuTask, toggleGym, updateLearning, saveLearningCard, deleteLearningCard, notify, settings, setSettings, selectPage, playAlarm }
  return <div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><span className="brand-mark"><Zap size={19} fill="currentColor" /></span><span>RiseUP</span></div>
      <p className="side-label">ORGANIZE</p>
      <Nav selected={page} onSelect={selectPage} />
      <div className="sidebar-tip"><div className="tip-icon">âœ¦</div><strong>Build your momentum</strong><p>Small daily actions lead to big changes.</p></div>
      <button className="profile" onClick={() => setEditingProfile(true)} aria-label="Edit profile"><Avatar user={user}/><div><strong>{user.name}</strong><small>@{user.username}</small></div><MoreHorizontal size={18}/></button>
    </aside>
    <main className="main-content">
      <header className="topbar"><div><p className="eyebrow">{formatDate(new Date(), 'EEEE, MMMM d')}</p><h1>{page === 'home' ? `Good morning, ${user.name.split(' ')[0]} ðŸ‘‹` : page[0].toUpperCase() + page.slice(1)}</h1></div><div className="top-actions"><button className="icon-button" onClick={() => notify('You are all caught up!')} aria-label="Notifications"><Bell size={20}/><span className="notification-dot"/></button><button className="mobile-profile-button" onClick={() => setEditingProfile(true)} aria-label="Edit profile"><Avatar user={user}/></button><button className="primary-button" onClick={() => setForm(blankTask())}><Plus size={19}/> Add task</button></div></header>
      {page === 'home' && <Dashboard {...shared} />}
      {page === 'tasks' && <TasksPage {...shared} />}
      {page === 'gym' && <GymPage {...shared} />}
      {page === 'learning' && <LearningPage {...shared} />}
      {page === 'progress' && <ProgressPage {...shared} gym={gym} />}
      {page === 'settings' && <SettingsPage {...shared} />}
    </main>
    <nav className="mobile-nav"><Nav selected={page} onSelect={selectPage} compact /></nav>
    {form && <TaskForm task={form} onClose={() => setForm(null)} onSave={saveTask} />}
    {editingProfile && <ProfileModal user={user} users={users} updateUser={updateUser} onSwitchUser={onSwitchUser} onClose={() => setEditingProfile(false)} notify={notify}/>}
    {toast && <div className="toast"><CheckCircle2 size={18}/>{toast}</div>}
  </div>
}

function Nav({ selected, onSelect, compact }) { return <div className={compact ? 'mobile-nav-items' : 'nav-links'}>{nav.map(([id, label, Icon]) => <button key={id} className={selected === id ? 'active' : ''} onClick={() => onSelect(id)}><Icon size={compact ? 19 : 20}/><span>{label}</span></button>)}</div> }

function Dashboard(p) { return <>
  <section className="hero-grid">
    <div className="progress-hero"><div className="section-top"><div><p className="eyebrow">TODAY'S PROGRESS</p><h2>Make today count.</h2></div><span className="calendar-chip"><CalendarDays size={16}/>{formatDate(new Date(), 'MMM d')}</span></div><div className="progress-summary"><div className="donut" style={{ '--value': `${p.percent * 3.6}deg` }}><span>{p.percent}<small>%</small></span></div><div><div className="big-progress"><b>{p.completed}</b><span>/ {p.todayTasks.length} tasks completed</span></div><div className="mini-progress"><i style={{ width: `${p.percent}%` }}/></div><p className="muted">{p.percent === 100 ? 'Everything is done. Enjoy your day!' : `${p.todayTasks.length - p.completed} task${p.todayTasks.length - p.completed === 1 ? '' : 's'} left to finish.`}</p></div></div><div className="stat-pills"><span><Flame size={17} fill="currentColor"/> {p.streak} day streak</span><span><Trophy size={17}/> Best: {Math.max(p.streak, 12)} days</span></div></div>
    <div className="quick-add"><div><span className="section-icon yellow"><Plus size={21}/></span><p className="eyebrow">QUICK ADD</p><h3>What's next?</h3></div><button onClick={() => p.setForm(blankTask())}><Plus size={19}/> Create a task</button><p>Keep the momentum going by planning your next win.</p></div>
  </section>
  <section className="dashboard-grid">
    <div className="panel task-panel"><div className="panel-header"><div><p className="eyebrow">FOCUS LIST</p><h2>Todayâ€™s tasks <span>{p.todayTasks.length}</span></h2></div><button className="text-button" onClick={() => p.selectPage('tasks')}>View all <ChevronRight size={16}/></button></div><div className="task-list">{p.todayTasks.length ? p.todayTasks.slice(0, 5).map(t => <TaskRow key={t.id} task={t} {...p}/>) : <Empty text="No tasks planned for today"/>}</div></div>
    <div className="right-stack"><WorkoutWidget {...p}/><LearningWidget {...p}/></div>
  </section>
  <section className="panel week-panel"><div className="panel-header"><div><p className="eyebrow">THIS WEEK</p><h2>Your consistency</h2></div><span className="trend"><Target size={16}/> {Math.round(p.week.reduce((a, b) => a + b.value, 0) / 7)}% average</span></div><WeeklyBars data={p.week}/></section>
</> }

function TaskRow({ task, toggleTask, setForm, removeTask, menuTask, setMenuTask }) { return <div className={`task-row ${task.completed ? 'done' : ''}`}><button className="check-button" onClick={() => toggleTask(task.id)} aria-label="Toggle task">{task.completed ? <Check size={15}/> : null}</button><div className="task-main"><strong>{task.title}</strong><div><span className={`tag ${task.category.toLowerCase()}`}>{task.category}</span>{task.time && <span className="task-time"><Clock3 size={13}/>{formatTime(task.time)}</span>}</div></div><div className="priority"><i className={task.priority.toLowerCase()}/>{task.priority}</div><div className="menu-wrap"><button className="dots" onClick={() => setMenuTask(menuTask === task.id ? null : task.id)}><Ellipsis size={19}/></button>{menuTask === task.id && <div className="task-menu"><button onClick={() => { setForm(task); setMenuTask(null) }}>Edit task</button><button className="danger" onClick={() => removeTask(task.id)}><Trash2 size={14}/> Delete</button></div>}</div></div> }

function WorkoutWidget({ workout, gymDone, toggleGym }) { return <div className={`workout-widget ${gymDone ? 'completed' : ''}`}><div className="widget-heading"><span className="section-icon purple"><Dumbbell size={20}/></span><div><p className="eyebrow">TODAY'S WORKOUT</p><h3>{workout.name}</h3></div><span className="workout-day">{workout.day.slice(0, 3)}</span></div>{workout.rest ? <p className="rest-note">Recovery is part of the program. Take it easy today.</p> : <><div className="exercise-pills">{workout.items.map(x => <span key={x}>{x}</span>)}</div><button className={gymDone ? 'complete-workout checked' : 'complete-workout'} onClick={toggleGym}>{gymDone ? <CheckCircle2 size={18}/> : <Circle size={18}/>} {gymDone ? 'Workout complete' : 'Mark workout complete'}</button></>}</div> }

function LearningWidget({ todayLearn, updateLearning, learning, selectPage }) { const cards = learning.cards || []; return <div className="learning-widget"><div className="widget-heading"><span className="section-icon blue"><Code2 size={20}/></span><div><p className="eyebrow">TODAY'S LEARNING</p><h3>Keep learning</h3></div><button className="mini-add" onClick={() => selectPage('learning')}><Plus size={15}/></button></div>{cards.length ? cards.slice(0, 3).map(card => <div className="learning-row" key={card.id}><span className="learning-dot" style={{ background: card.color }}/><div><strong>{card.title}</strong><small>{card.total} total {card.unit}</small></div><div className="counter-control"><button onClick={() => updateLearning(card.id, (todayLearn[card.id] || 0) - 1)}>âˆ’</button><b>{todayLearn[card.id] || 0}</b><button onClick={() => updateLearning(card.id, (todayLearn[card.id] || 0) + 1)}>+</button></div></div>) : <div className="learning-empty"><BookOpen size={17}/><span>No learning cards yet</span><button onClick={() => selectPage('learning')}>Add one</button></div>}</div> }

function TasksPage(p) { const [filter, setFilter] = useState('All'); const filtered = p.tasks.filter(t => filter === 'All' || (filter === 'Today' && t.dueDate === dateKey()) || t.category === filter); return <><div className="page-toolbar"><div className="filters">{['All', 'Today', ...categories].map(x => <button key={x} onClick={() => setFilter(x)} className={filter === x ? 'selected' : ''}>{x}</button>)}</div><div className="task-count">{filtered.length} tasks</div></div><section className="panel all-tasks"><div className="task-list">{filtered.length ? filtered.map(t => <TaskRow key={t.id} task={t} {...p}/>) : <Empty text="No matching tasks yet"/>}</div></section></> }

function GymPage(p) { const selected = workoutForDate(new Date()); const selectedDone = Boolean(p.gym[dateKey()]); return <><section className="gym-hero"><div><span className="section-icon purple big"><Dumbbell size={28}/></span><p className="eyebrow">WEEKLY TRAINING PLAN</p><h2>{selected.day} â€” {selected.name}</h2><p>{selected.rest ? 'A rest day keeps you ready for your next session.' : 'Show up, do the work, and take care of your body.'}</p></div><div className="workout-status"><span>{selectedDone ? 'DONE' : 'SCHEDULED'}</span><strong>{selectedDone ? 'Workout completed' : 'Ready to train'}</strong></div></section><section className="gym-layout"><div className="panel workout-detail"><p className="eyebrow">TODAY'S SESSION</p><h2>{selected.name}</h2>{selected.rest ? <Empty text="Rest, recover, and get ready for the week ahead."/> : <>{selected.items.map((item, i) => <div className="exercise-row" key={item}><span>{i + 1}</span><div><strong>{item} focus</strong><small>3â€“4 sets Â· controlled form</small></div><CheckCircle2 size={20}/></div>)}<button className="primary-button wide" onClick={p.toggleGym}>{selectedDone ? <Check/> : <Dumbbell size={18}/>}{selectedDone ? 'Workout completed' : 'Complete workout'}</button></>}</div><div className="panel weekly-plan"><p className="eyebrow">YOUR SPLIT</p>{['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'].map((day, index) => { const w = workoutForDate(new Date(2024, 0, index + 1)); return <div className={day === selected.day ? 'split-row active' : 'split-row'} key={day}><span>{day.slice(0,3)}</span><strong>{w.name}</strong>{w.rest ? <span>Rest</span> : <Dumbbell size={16}/>}</div> })}</div></section></> }

function LearningPage(p) { const [editing, setEditing] = useState(null); const cards = p.learning.cards || []; return <><section className="learning-hero"><div><p className="eyebrow">CODING & LEARNING</p><h2>Practice with intention.</h2><p>Log what you finish today. Your totals and streaks update automatically.</p></div><button className="primary-button" onClick={() => setEditing(blankLearningCard())}><Plus size={18}/> Add learning card</button></section>{cards.length ? <div className="learning-page-grid">{cards.map(card => <LearningGoal key={card.id} card={card} today={p.todayLearn[card.id] || 0} onChange={n => p.updateLearning(card.id, n)} onEdit={() => setEditing(card)} onDelete={() => p.deleteLearningCard(card.id)}/>)}</div> : <section className="empty-learning"><span className="section-icon blue"><BookOpen size={20}/></span><h3>Your learning space is ready</h3><p>Add a card for HackerRank, a course, a book, DSA practice, or anything else you want to track.</p><button className="primary-button" onClick={() => setEditing(blankLearningCard())}><Plus size={18}/> Add your first card</button></section>}<section className="panel study-tip"><BookOpen size={22}/><div><strong>Make learning a daily appointment</strong><p>Add a recurring task with a reminder so your coding practice has a place in your day.</p></div><button className="secondary-button" onClick={() => p.setForm({ ...blankTask(), title: 'Coding practice', category: 'Coding', recurrence: 'Daily', time: '19:00' })}>Set reminder</button></section>{editing && <LearningCardForm card={editing} onClose={() => setEditing(null)} onSave={card => { p.saveLearningCard(card); setEditing(null); p.notify(card.id ? 'Learning card updated' : 'Learning card added') }}/>}</> }

function LearningGoal({ card, today, onChange, onEdit, onDelete }) { return <article className="learning-goal"><div className="goal-top"><span style={{ background: card.color }}>{card.short || card.title.slice(0,2)}</span><div><h3>{card.title}</h3><p>{card.description || 'Track your daily progress.'}</p></div><div className="card-actions"><button onClick={onEdit}>Edit</button><button onClick={onDelete} aria-label={`Delete ${card.title}`}><Trash2 size={15}/></button></div></div><div className="goal-total"><b>{card.total}</b><span>{card.unit}<br/>all time</span></div><div className="log-today"><span>Today</span><div className="counter-control large"><button onClick={() => onChange(today - 1)}>âˆ’</button><b>{today}</b><button onClick={() => onChange(today + 1)}>+</button></div></div></article> }

function ProgressPage({ tasks, week, gym, learning }) { const [selectedDate, setSelectedDate] = useState(dateKey()); const totals = { completed: tasks.filter(t => t.completed).length, missed: tasks.filter(t => !t.completed && t.dueDate < dateKey()).length, gym: Object.values(gym).filter(Boolean).length }; const history = tasks.filter(t => t.dueDate === selectedDate).sort((a,b) => Number(a.completed) - Number(b.completed)); const learningTotal = (learning.cards || []).reduce((sum, card) => sum + card.total, 0); return <><section className="metric-grid"><Metric icon={<CheckCircle2/>} label="Tasks completed" value={totals.completed} trend="All time"/><Metric icon={<Dumbbell/>} label="Gym sessions" value={totals.gym} trend="This month"/><Metric icon={<Code2/>} label="Learning logged" value={learningTotal} trend="All time"/><Metric icon={<Flame/>} label="Best streak" value="12 days" trend="Keep it alive"/></section><section className="panel progress-chart"><div className="panel-header"><div><p className="eyebrow">WEEKLY PROGRESS</p><h2>How your week is going</h2></div><span className="calendar-chip">Last 7 days</span></div><WeeklyBars data={week} tall/></section><section className="progress-lower"><CalendarView tasks={tasks} selectedDate={selectedDate} onSelect={setSelectedDate}/><section className="history-section"><div><p className="eyebrow">ACTIVITY HISTORY</p><h2>{formatDate(new Date(`${selectedDate}T12:00:00`), 'MMMM d')}</h2></div><div className="history-list">{history.length ? history.map(t => <div className="history-row" key={t.id}><span className={t.completed ? 'history-check good' : 'history-check'}>{t.completed ? <Check size={14}/> : <X size={14}/>}</span><div><strong>{t.title}</strong><small>{t.category} Â· {t.time ? formatTime(t.time) : 'No reminder'}</small></div><span>{t.completed ? 'Completed' : 'Pending'}</span></div>) : <Empty text="No planned tasks for this day."/>}</div></section></section></> }

function CalendarView({ tasks, selectedDate, onSelect }) { const now = new Date(); const first = new Date(now.getFullYear(), now.getMonth(), 1); const days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate(); const blanks = (first.getDay() + 6) % 7; return <section className="panel calendar-panel"><p className="eyebrow">CALENDAR</p><h2>{formatDate(now, 'MMMM')}</h2><div className="calendar-weekdays">{['M','T','W','T','F','S','S'].map((d,i) => <span key={`${d}${i}`}>{d}</span>)}</div><div className="calendar-days">{Array.from({ length: blanks }, (_, i) => <i key={`blank-${i}`}/>)}{Array.from({ length: days }, (_, i) => { const d = new Date(now.getFullYear(), now.getMonth(), i + 1); const key = dateKey(d); const planned = tasks.filter(t => t.dueDate === key); const done = planned.filter(t => t.completed).length; return <button key={key} onClick={() => onSelect(key)} className={`${key === selectedDate ? 'selected' : ''} ${key === dateKey() ? 'today' : ''}`}><span>{i + 1}</span>{planned.length > 0 && <small className={done === planned.length ? 'all-done' : ''}>{done}/{planned.length}</small>}</button> })}</div><p className="calendar-key"><i/> completed / planned</p></section> }

function Metric({ icon, label, value, trend }) { return <div className="metric-card"><span>{icon}</span><p>{label}</p><b>{value}</b><small>{trend}</small></div> }

function Avatar({ user, large = false }) { const initials = (user.name || user.username || '?').split(' ').map(part => part[0]).join('').slice(0, 2).toUpperCase(); return <div className={`avatar ${large ? 'large-avatar' : ''}`}>{user.photo ? <img src={user.photo} alt={`${user.name}'s profile`}/> : initials}</div> }

function AccountScreen({ users, onChoose, onCreate }) { const [draft, setDraft] = useState({ name: '', username: '' }); const [error, setError] = useState(''); const submit = event => { event.preventDefault(); const username = draft.username.trim().replace(/^@+/, ''); if (!/^[a-zA-Z0-9_-]{3,24}$/.test(username)) return setError('Use 3â€“24 letters, numbers, _ or - for your username.'); if (!onCreate(draft)) setError('That username is already in use on this device.') }; return <main className="account-screen"><section className="account-card"><div className="brand account-brand"><span className="brand-mark"><Zap size={19} fill="currentColor"/></span><span>RiseUP</span></div><p className="eyebrow">YOUR PERSONAL WORKSPACE</p><h1>{users.length ? 'Choose a workspace' : 'Create your workspace'}</h1><p className="account-copy">Every username has separate tasks, workouts, learning goals, and settings on this device.</p>{users.length > 0 && <div className="account-list">{users.map(user => <button key={user.id} className="account-user" onClick={() => onChoose(user.id)}><Avatar user={user}/><span><strong>{user.name}</strong><small>@{user.username}</small></span><ChevronRight size={18}/></button>)}</div>}<form className="account-form" onSubmit={submit}><div className="account-form-title"><UserPlus size={18}/><strong>{users.length ? 'Create another workspace' : 'Set up your profile'}</strong></div><label className="input-label">Display name<input required placeholder="e.g. Aisha Khan" value={draft.name} onChange={event => setDraft(current => ({ ...current, name: event.target.value }))}/></label><label className="input-label">Username<input required placeholder="e.g. aisha" value={draft.username} onChange={event => { setDraft(current => ({ ...current, username: event.target.value })); setError('') }}/></label>{error && <p className="form-error">{error}</p>}<button className="primary-button" type="submit"><UserRound size={17}/> Create workspace</button></form></section></main> }

function ProfileModal({ user, users, updateUser, onSwitchUser, onClose, notify }) { const [draft, setDraft] = useState({ name: user.name, username: user.username, photo: user.photo || '' }); const photoInput = useRef(null); const pickPhoto = event => { const file = event.target.files?.[0]; if (!file) return; if (!file.type.startsWith('image/')) return notify('Please choose an image file'); if (file.size > 1500000) return notify('Choose an image smaller than 1.5 MB'); const reader = new FileReader(); reader.onload = () => setDraft(current => ({ ...current, photo: String(reader.result) })); reader.readAsDataURL(file) }; const save = event => { event.preventDefault(); const username = draft.username.trim().replace(/^@+/, ''); if (!draft.name.trim()) return notify('Enter a display name'); if (!/^[a-zA-Z0-9_-]{3,24}$/.test(username)) return notify('Username must be 3â€“24 letters, numbers, _ or -'); if (users.some(item => item.id !== user.id && item.username.toLowerCase() === username.toLowerCase())) return notify('That username is already in use'); updateUser({ name: draft.name.trim(), username, photo: draft.photo }); notify('Profile updated'); onClose() }; return <div className="modal-backdrop" onMouseDown={onClose}><form className="task-modal profile-modal" onMouseDown={event => event.stopPropagation()} onSubmit={save}><div className="modal-header"><div><p className="eyebrow">EDIT PROFILE</p><h2>Make this workspace yours</h2></div><button type="button" className="icon-button" onClick={onClose}><X/></button></div><div className="profile-editor"><Avatar user={{ ...user, ...draft }} large/><div><button type="button" className="secondary-button" onClick={() => photoInput.current?.click()}><Camera size={15}/> {draft.photo ? 'Change photo' : 'Add photo'}</button>{draft.photo && <button type="button" className="text-button remove-photo" onClick={() => setDraft(current => ({ ...current, photo: '' }))}>Remove</button>}<input ref={photoInput} className="hidden-input" type="file" accept="image/*" onChange={pickPhoto}/><small>JPG, PNG, or WebP Â· up to 1.5 MB</small></div></div><div className="form-two"><label className="input-label">Display name<input value={draft.name} onChange={event => setDraft(current => ({ ...current, name: event.target.value }))}/></label><label className="input-label">Username<input value={draft.username} onChange={event => setDraft(current => ({ ...current, username: event.target.value }))}/></label></div><div className="modal-actions"><button className="secondary-button" type="button" onClick={onSwitchUser}><LogOut size={16}/> Switch user</button><button className="primary-button" type="submit"><Check size={17}/> Save profile</button></div></form></div> }

function SettingsPage({ settings, setSettings, notify, tasks, setTasks, gym, setGym, learning, setLearning, dailyHistory, playAlarm }) { const enableNotifications = async () => { if (!('Notification' in window)) return notify('Notifications are not supported in this browser'); const result = await Notification.requestPermission(); if (result === 'granted') { setSettings(s => ({ ...s, notifications: true })); playAlarm(); notify('Task reminders enabled') } else notify('Notification permission was not granted') }; const exportData = () => { const file = new Blob([JSON.stringify({ tasks, gym, learning, dailyHistory, settings, exportedAt: new Date().toISOString() }, null, 2)], { type: 'application/json' }); const url = URL.createObjectURL(file); const a = document.createElement('a'); a.href = url; a.download = `riseup-backup-${dateKey()}.json`; a.click(); URL.revokeObjectURL(url); notify('Backup downloaded') }; const restoreData = event => { const file = event.target.files?.[0]; if (!file) return; const reader = new FileReader(); reader.onload = () => { try { const backup = JSON.parse(reader.result); if (!Array.isArray(backup.tasks)) throw new Error(); setTasks(backup.tasks); setGym(backup.gym || {}); setLearning({ ...defaultLearning, ...(backup.learning || {}), cards: backup.learning?.cards || [] }); if (backup.settings) setSettings(backup.settings); notify('Backup restored') } catch { notify('That backup file is not valid') } }; reader.readAsText(file) }; const clearData = () => { if (!window.confirm('Delete every saved task, workout, and learning record from this browser?')) return; setTasks([]); setGym({}); setLearning(defaultLearning); notify('All activity data cleared') }; return <div className="settings-grid"><section className="panel settings-panel"><p className="eyebrow">APPEARANCE</p><h2>Make it yours</h2><label>Theme<div className="theme-options">{['light', 'dark', 'system'].map(t => <button onClick={() => setSettings(s => ({...s, theme: t}))} className={settings.theme === t ? 'selected' : ''} key={t}>{t[0].toUpperCase()+t.slice(1)}</button>)}</div></label></section><section className="panel settings-panel"><p className="eyebrow">REMINDERS</p><h2>Stay on track</h2><label className="switch-line"><div><strong>Browser notifications</strong><small>Enable this so task and gym alerts can be delivered.</small></div><button className={settings.notifications ? 'switch on' : 'switch'} onClick={enableNotifications}><i/></button></label><label className="switch-line alarm-line"><div><strong>Reminder alarm</strong><small>Play a short alert sound with each reminder.</small></div><button className={settings.alarm ? 'switch on' : 'switch'} onClick={() => { setSettings(s => ({ ...s, alarm: !s.alarm })); if (!settings.alarm) playAlarm() }}><i/></button></label><label className="switch-line alarm-line"><div><strong>Daily gym alarm</strong><small>"Time to go GYM!" at 4:30 PM every day.</small></div><button className={settings.gymAlarm !== false ? 'switch on' : 'switch'} onClick={() => setSettings(s => ({ ...s, gymAlarm: s.gymAlarm === false }))}><i/></button></label><label className="input-label">Gym alarm time<input type="time" value={settings.gymAlarmTime || '16:30'} onChange={e => setSettings(s => ({...s, gymAlarmTime: e.target.value}))}/></label><label className="input-label">Default reminder time<input type="time" value={settings.defaultReminder} onChange={e => setSettings(s => ({...s, defaultReminder: e.target.value}))}/></label></section><section className="panel settings-panel wide-settings"><p className="eyebrow">DATA & BACKUP</p><h2>Your data stays on this device</h2><p className="muted">Tasks, workouts, learning cards, daily archives, and logs are saved automatically. You can download a portable backup whenever you like and restore it on this device.</p><div className="data-actions"><button className="secondary-button" onClick={exportData}>Export backup</button><label className="secondary-button restore-button">Restore backup<input type="file" accept="application/json" onChange={restoreData}/></label><button className="delete-data" onClick={clearData}><Trash2 size={15}/> Delete all data</button></div></section></div> }

function WeeklyBars({ data, tall = false }) { return <div className={`weekly-bars ${tall ? 'tall' : ''}`}>{data.map((day, i) => <div className="bar-col" key={day.key}><div className="bar-value">{day.value}%</div><div className="bar-track"><i style={{ height: `${Math.max(day.value, 5)}%` }} className={i === data.length - 1 ? 'today-bar' : ''}/></div><span>{day.label}</span></div>)}</div> }

function TaskForm({ task, onClose, onSave }) { const [draft, setDraft] = useState(task); const update = (key, value) => setDraft(x => ({ ...x, [key]: value })); return <div className="modal-backdrop" onMouseDown={onClose}><form className="task-modal" onMouseDown={e => e.stopPropagation()} onSubmit={e => { e.preventDefault(); onSave(draft) }}><div className="modal-header"><div><p className="eyebrow">{task.id ? 'EDIT TASK' : 'NEW TASK'}</p><h2>{task.id ? 'Update task' : 'Plan something great'}</h2></div><button type="button" className="icon-button" onClick={onClose}><X/></button></div><label className="input-label">Task name<input autoFocus required placeholder="e.g. Complete Python loops practice" value={draft.title} onChange={e => update('title', e.target.value)}/></label><div className="form-two"><label className="input-label">Category<select value={draft.category} onChange={e => update('category', e.target.value)}>{categories.map(x => <option key={x}>{x}</option>)}</select></label><label className="input-label">Priority<select value={draft.priority} onChange={e => update('priority', e.target.value)}>{['Low','Medium','High'].map(x => <option key={x}>{x}</option>)}</select></label></div><div className="form-two"><label className="input-label">Due date<input type="date" value={draft.dueDate} onChange={e => update('dueDate', e.target.value)}/></label><label className="input-label">Reminder time<input type="time" value={draft.time} onChange={e => update('time', e.target.value)}/></label></div><label className="input-label">Repeat<select value={draft.recurrence} onChange={e => update('recurrence', e.target.value)}>{['None','Daily','Weekdays','Weekly'].map(x => <option key={x}>{x}</option>)}</select></label><label className="input-label">Notes <textarea placeholder="Add details, links, or a small goalâ€¦" value={draft.notes} onChange={e => update('notes', e.target.value)}/></label><div className="modal-actions"><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button className="primary-button" type="submit"><Check size={18}/>{task.id ? 'Save changes' : 'Add task'}</button></div></form></div> }

function LearningCardForm({ card, onClose, onSave }) { const [draft, setDraft] = useState(card); const update = (key, nextValue) => setDraft(current => ({ ...current, [key]: nextValue })); return <div className="modal-backdrop" onMouseDown={onClose}><form className="task-modal" onMouseDown={event => event.stopPropagation()} onSubmit={event => { event.preventDefault(); onSave(draft) }}><div className="modal-header"><div><p className="eyebrow">{card.id ? 'EDIT LEARNING CARD' : 'NEW LEARNING CARD'}</p><h2>{card.id ? 'Update your tracker' : 'Track something new'}</h2></div><button type="button" className="icon-button" onClick={onClose}><X/></button></div><label className="input-label">Card title<input autoFocus required placeholder="e.g. LeetCode, React course, Reading" value={draft.title} onChange={event => update('title', event.target.value)}/></label><label className="input-label">Description<input placeholder="What are you working toward?" value={draft.description} onChange={event => update('description', event.target.value)}/></label><div className="form-two"><label className="input-label">Unit<select value={draft.unit} onChange={event => update('unit', event.target.value)}>{['problems solved','topics completed','lessons completed','chapters read','sessions'].map(item => <option key={item}>{item}</option>)}</select></label><label className="input-label">Card color<input type="color" value={draft.color} onChange={event => update('color', event.target.value)}/></label></div><div className="modal-actions"><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button className="primary-button" type="submit"><Check size={18}/>{card.id ? 'Save changes' : 'Add card'}</button></div></form></div> }

function Empty({ text }) { return <div className="empty"><CheckCircle2 size={23}/><span>{text}</span></div> }
function userStorageKey(userId, key) { return `${storagePrefix}.user.${userId}.${key}` }
function legacyUserStorageKey(userId, key) { return `${legacyStoragePrefix}.user.${userId}.${key}` }
function isStoredValueValid(value, initial) { if (Array.isArray(initial)) return Array.isArray(value); if (initial && typeof initial === 'object') return Boolean(value) && typeof value === 'object' && !Array.isArray(value); return typeof value === typeof initial }
function readStoredValue(key, initial) { try { const raw = localStorage.getItem(key); if (!raw) return initial; const value = JSON.parse(raw); return isStoredValueValid(value, initial) ? value : initial } catch { return initial } }
function useUserStoredState(user, key, initial) { const storageKey = userStorageKey(user.id, key); const [state, setState] = useState(() => { if (localStorage.getItem(storageKey)) return readStoredValue(storageKey, initial); const legacyScopedKey = legacyUserStorageKey(user.id, key); if (localStorage.getItem(legacyScopedKey)) return readStoredValue(legacyScopedKey, initial); return user.legacyDataOwner ? readStoredValue(`${legacyStoragePrefix}.${key}`, initial) : initial }); useEffect(() => localStorage.setItem(storageKey, JSON.stringify(state)), [storageKey, state]); return [state, setState] }
function useStoredState(key, initial, legacyKey) { const [state, setState] = useState(() => localStorage.getItem(key) ? readStoredValue(key, initial) : legacyKey ? readStoredValue(legacyKey, initial) : initial); useEffect(() => localStorage.setItem(key, JSON.stringify(state)), [key, state]); return [state, setState] }
function formatTime(time) { const [h, m] = time.split(':').map(Number); return `${h % 12 || 12}:${String(m).padStart(2,'0')} ${h >= 12 ? 'PM' : 'AM'}` }
function addMinutes(time, minutes) { if (!time) return new Date(Date.now() + minutes * 60000).toTimeString().slice(0, 5); const [hours, mins] = time.split(':').map(Number); return new Date(2000, 0, 1, hours, mins + minutes).toTimeString().slice(0, 5) }
function makeDailySnapshot(key, tasks, gym, learning) { const dayTasks = tasks.filter(task => task.dueDate === key); return { date: key, tasksTotal: dayTasks.length, tasksCompleted: dayTasks.filter(task => task.completed).length, gymCompleted: Boolean(gym[key]), learning: learning.dates?.[key] || {}, savedAt: new Date().toISOString() } }
function weeklyData(tasks) { const start = startOfWeek(new Date()); return Array.from({ length: 7 }, (_, i) => { const d = new Date(start); d.setDate(d.getDate() + i); const key = dateKey(d); const list = tasks.filter(t => t.dueDate === key); return { key, label: formatDate(d, 'EEE'), value: list.length ? Math.round(list.filter(t => t.completed).length / list.length * 100) : 0 } }) }

export default App
