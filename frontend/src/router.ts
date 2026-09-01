import { ref } from 'vue';

export type Route =
  | { name: 'home' }
  | { name: 'transactions' }
  | { name: 'work'; id: number | null; source: 'home' | 'transactions' };

function routeFromLocation(): Route {
  const path = window.location.pathname.replace(/\/$/, '') || '/';
  if (path === '/transactions') return { name: 'transactions' };
  if (path === '/transactions/new') {
    const source = new URLSearchParams(window.location.search).get('source') === 'transactions' ? 'transactions' : 'home';
    return { name: 'work', id: null, source };
  }
  const match = path.match(/^\/transactions\/(\d+)$/);
  if (match) {
    const source = new URLSearchParams(window.location.search).get('source') === 'home' ? 'home' : 'transactions';
    return { name: 'work', id: Number(match[1]), source };
  }
  return { name: 'home' };
}

export const currentRoute = ref<Route>(routeFromLocation());

export function navigate(path: string): void {
  window.history.pushState({}, '', path);
  currentRoute.value = routeFromLocation();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

window.addEventListener('popstate', () => {
  currentRoute.value = routeFromLocation();
});
