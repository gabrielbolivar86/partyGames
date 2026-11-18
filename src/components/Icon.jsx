import { useEffect, useState } from 'react'
import {
  IconConfetti, IconPumpkinScary, IconChristmasTree, IconBabyCarriage, IconHelpHexagon, IconLeaf, IconDroplet,
  IconCircle, IconCrown, IconCheck, IconX, IconPlus, IconArrowRight, IconArrowLeft, IconArrowUp, IconArrowDown,
  IconHome, IconUsers, IconUserPlus, IconTrophy, IconStar, IconDeviceTv, IconLink, IconCopy, IconQrcode,
  IconSettings, IconTrash, IconRefresh, IconKey, IconEye, IconEyeOff, IconClock, IconWifi, IconLogout,
  IconMasksTheater, IconSearch, IconUserQuestion, IconSpy, IconGift, IconMoon, IconSun, IconBell, IconLock,
  IconPlayerPlay, IconPlayerPause, IconPlayerStop, IconPrinter, IconPalette, IconDeviceGamepad2, IconAlertTriangle,
  IconInfoCircle, IconHandStop, IconDice5, IconSparkles, IconListNumbers, IconCoin, IconMicrophone2,
} from '@tabler/icons-react'
import { getTheme } from '../lib/themes'

// Solo se empaquetan los íconos de esta lista (importar todo Tabler pesa 4 MB).
const ICONS = {
  IconConfetti, IconPumpkinScary, IconChristmasTree, IconBabyCarriage, IconHelpHexagon, IconLeaf, IconDroplet,
  IconCircle, IconCrown, IconCheck, IconX, IconPlus, IconArrowRight, IconArrowLeft, IconArrowUp, IconArrowDown,
  IconHome, IconUsers, IconUserPlus, IconTrophy, IconStar, IconDeviceTv, IconLink, IconCopy, IconQrcode,
  IconSettings, IconTrash, IconRefresh, IconKey, IconEye, IconEyeOff, IconClock, IconWifi, IconLogout,
  IconMasksTheater, IconSearch, IconUserQuestion, IconSpy, IconGift, IconMoon, IconSun, IconBell, IconLock,
  IconPlayerPlay, IconPlayerPause, IconPlayerStop, IconPrinter, IconPalette, IconDeviceGamepad2, IconAlertTriangle,
  IconInfoCircle, IconHandStop, IconDice5, IconSparkles, IconListNumbers, IconCoin, IconMicrophone2,
}

// Íconos de trazo grueso y uniforme (Tabler). Uso: <Icon name="IconCrown" size={20} />
export function Icon({ name, size = 22, stroke = 2.25, ...rest }) {
  const Cmp = ICONS[name] || IconCircle
  return <Cmp size={size} stroke={stroke} aria-hidden="true" {...rest} />
}

// Ícono del tema activo (lee <html data-theme> y se actualiza si cambia)
export function ThemeIcon(props) {
  const [id, setId] = useState(() => document.documentElement.dataset.theme)
  useEffect(() => {
    const obs = new MutationObserver(() => setId(document.documentElement.dataset.theme))
    obs.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    return () => obs.disconnect()
  }, [])
  return <Icon name={getTheme(id).icon} {...props} />
}
